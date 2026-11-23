import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../domain/expense.dart';
import '../domain/quad.dart';
import '../domain/receipt_parser.dart';
import '../domain/receipt_text_reader.dart';
import 'expense_api.dart';
import 'file_store.dart';
import 'local_store.dart';
import 'sync_service.dart';

/// Point d'entrée de l'UI : toute action est d'abord enregistrée localement,
/// puis la synchronisation est déclenchée (et rejouée plus tard si hors-ligne).
class ExpenseRepository extends ChangeNotifier {
  ExpenseRepository({
    required LocalStore store,
    required FileStore files,
    required http.Client httpClient,
    this.pollInterval = const Duration(seconds: 4),
    this._textReader,
  }) : _store = store,
       _files = files {
    _sync = SyncService(
      store: store,
      api: ExpenseApi(client: httpClient, settings: () => _settings),
      files: files,
    );
  }

  final LocalStore _store;
  final FileStore _files;

  /// Lecture du justificatif sur l'appareil (`null` : indisponible, ex. desktop).
  final ReceiptTextReader? _textReader;
  late final SyncService _sync;

  /// Intervalle de rafraîchissement tant qu'un traitement serveur est en cours (`null` = désactivé).
  final Duration? pollInterval;

  ServerSettings _settings = const ServerSettings(baseUrl: '');
  List<Expense> _all = const [];
  Future<SyncReport?>? _running;
  bool _syncAgain = false;
  Timer? _poll;
  SyncReport? _lastReport;
  bool _disposed = false;

  ServerSettings get settings => _settings;

  /// Dépenses visibles (non supprimées), dans l'ordre de la base.
  List<Expense> get expenses =>
      List.unmodifiable(_all.where((e) => !e.deleted));

  SyncReport? get lastReport => _lastReport;

  bool get isSyncing => _running != null;

  Expense? byId(String id) {
    for (final e in _all) {
      if (e.id == id) return e;
    }
    return null;
  }

  Future<void> load() async {
    _settings = ServerSettings(
      baseUrl: await _store.setting('baseUrl') ?? '',
      token: await _store.setting('token') ?? '',
    );
    await _reload();
  }

  Future<void> saveSettings(ServerSettings settings) async {
    await _store.setSetting('baseUrl', settings.baseUrl.trim());
    await _store.setSetting('token', settings.token.trim());
    _settings = settings;
    _notify();
    await sync();
  }

  /// Scan sur l'appareil : la photo brute est conservée telle quelle (original), l'image
  /// recadrée et filtrée localement est visible immédiatement, même hors-ligne.
  Future<Expense> captureScan(
    String photoPath,
    Quad corners,
    ImageFilter filter, {
    required List<int> processedJpeg,
  }) async {
    final id = const Uuid().v4();
    final original = await _files.saveOriginal(id, photoPath);
    final processed = await _files.saveProcessed(id, processedJpeg);
    final expense = Expense.draft(
      id: id,
      originalPath: original.path,
      filter: filter,
    ).copyWith(corners: corners, cropped: true, processedPath: processed.path);
    await _store.save(expense);
    await _reload();
    await _readReceipt(id, processed.path);
    await sync();
    return byId(id) ?? expense;
  }

  /// Pré-remplit la dépense avec ce que l'OCR de l'appareil lit sur l'image recadrée. Un échec
  /// est journalisé sans bloquer : la dépense reste enregistrée et se complète à la main.
  Future<void> _readReceipt(String id, String imagePath) async {
    final reader = _textReader;
    if (reader == null) return;
    try {
      final text = await reader.read(imagePath);
      if (text == null) return;
      final guess = const ReceiptParser().parse(text);
      // Une synchro en cours réenregistrerait sa copie antérieure par-dessus le pré-remplissage.
      while (_running != null) {
        await _running;
      }
      final current = await _store.get(id);
      if (current == null || current.deleted) return;
      final prefilled = current.withDeviceGuess(guess);
      if (prefilled == current) return;
      await _store.save(prefilled);
      await _reload();
    } on Object catch (e, st) {
      debugPrint('Lecture du justificatif impossible : $e\n$st');
    }
  }

  Future<void> edit(Expense edited) async {
    final current = byId(edited.id);
    if (current == null) return;
    await _saveAndSync(current.withEditedFields(edited));
  }

  /// Nouveau traitement depuis l'original : autre filtre et/ou contour réajusté.
  /// [processedJpeg] : aperçu calculé sur l'appareil, affiché sans attendre le serveur.
  Future<void> reprocess(
    String id,
    ImageFilter filter, {
    Quad? corners,
    List<int>? processedJpeg,
  }) async {
    final current = byId(id);
    if (current == null) return;
    final pendingUpload = current.syncState == SyncState.pendingUpload;
    final processed = processedJpeg == null
        ? null
        : await _files.saveProcessed(id, processedJpeg);
    await _saveAndSync(
      current.copyWith(
        filter: filter,
        corners: corners,
        processedPath: processed?.path,
        cropped: corners != null ? true : null,
        status: ProcessingStatus.pending,
        syncState: pendingUpload
            ? SyncState.pendingUpload
            : SyncState.pendingReprocess,
      ),
    );
  }

  Future<void> delete(String id) async {
    final current = byId(id);
    if (current == null) return;
    await _saveAndSync(
      current.copyWith(deleted: true, syncState: SyncState.pendingDelete),
    );
  }

  /// Lance une synchronisation ; un appel pendant une synchro en cours la fait rejouer à la fin.
  Future<SyncReport?> sync() {
    if (_running != null) {
      _syncAgain = true;
      return _running!;
    }
    if (!_settings.isConfigured) return Future.value(null);
    _running = _runSync();
    _notify();
    return _running!;
  }

  Future<SyncReport?> _runSync() async {
    try {
      do {
        _syncAgain = false;
        _lastReport = await _sync.sync();
        await _reload();
      } while (_syncAgain);
    } finally {
      _running = null;
      _notify();
    }
    _schedulePollIfProcessing();
    return _lastReport;
  }

  void _schedulePollIfProcessing() {
    _poll?.cancel();
    final interval = pollInterval;
    if (interval == null || _disposed) return;
    final waiting = _all.any(
      (e) => !e.deleted && e.status == ProcessingStatus.pending,
    );
    if (waiting && !(_lastReport?.offline ?? false)) {
      _poll = Timer(interval, sync);
    }
  }

  Future<void> _saveAndSync(Expense e) async {
    await _store.save(e);
    await _reload();
    await sync();
  }

  Future<void> _reload() async {
    _all = await _store.all();
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    super.dispose();
  }
}

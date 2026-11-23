import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../domain/expense.dart';
import '../domain/quad.dart';
import '../domain/receipt_parser.dart';
import '../domain/receipt_text_reader.dart';
import 'account_repository.dart';
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
    required AccountRepository account,
    this.pollInterval = const Duration(seconds: 4),
    this._textReader,
  }) : _store = store,
       _files = files,
       _account = account,
       _wasConnected = account.connected {
    _account.addListener(_onAccountChanged);
    _sync = SyncService(
      store: store,
      api: ExpenseApi(
        client: httpClient,
        settings: () => _account.settings,
        token: () => _account.session?.token,
      ),
      files: files,
    );
  }

  final LocalStore _store;
  final FileStore _files;
  final AccountRepository _account;

  /// Lecture du justificatif sur l'appareil (`null` : indisponible, ex. desktop).
  final ReceiptTextReader? _textReader;
  late final SyncService _sync;
  bool _wasConnected;

  /// Intervalle de rafraîchissement tant qu'un traitement serveur est en cours (`null` = désactivé).
  final Duration? pollInterval;

  List<Expense> _all = const [];
  Future<SyncReport?>? _running;
  bool _syncAgain = false;
  Timer? _poll;
  SyncReport? _lastReport;
  bool _disposed = false;

  /// Synchronisation avec le serveur possible (adresse renseignée et compte connecté).
  bool get withServer => _account.connected;

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

  Future<void> load() => _reload();

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
    if (!_account.connected) return Future.value(null);
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
      } while (_syncAgain && !_lastReport!.unauthorized);
    } finally {
      _running = null;
      _notify();
    }
    final report = _lastReport!;
    // Données locales conservées : elles repartiront à la prochaine connexion.
    if (report.unauthorized) await _account.expire();
    // L'usage de l'espace en ligne a changé (ou l'espace est plein) : la page Compte le reflète.
    if (!report.offline &&
        !report.unauthorized &&
        (report.pushed > 0 || report.refusedForQuota > 0)) {
      await _account.refresh();
    }
    _schedulePollIfProcessing();
    return _lastReport;
  }

  /// À la connexion (éventuellement à un autre compte), tout est récupéré et les dépenses
  /// locales en attente partent vers le compte : l'envoi est idempotent (UUID du client).
  Future<void> _onAccountChanged() async {
    final connected = _account.connected;
    final justConnected = connected && !_wasConnected;
    _wasConnected = connected;
    _notify();
    if (!justConnected) return;
    await _store.clearLastSync();
    await sync();
  }

  void _schedulePollIfProcessing() {
    _poll?.cancel();
    final interval = pollInterval;
    if (interval == null || _disposed) return;
    // Seules les dépenses déjà reçues par le serveur sont en cours de traitement ; une capture
    // non envoyée (refusée faute d'espace…) attend la prochaine synchro, sans boucle.
    final waiting = _all.any(
      (e) =>
          !e.deleted &&
          e.status == ProcessingStatus.pending &&
          e.syncState == SyncState.synced,
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
    _account.removeListener(_onAccountChanged);
    _disposed = true;
    _poll?.cancel();
    super.dispose();
  }
}

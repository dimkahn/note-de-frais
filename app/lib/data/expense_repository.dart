import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../domain/expense.dart';
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

  /// Copie la photo dans le stockage de l'app (original conservé tel quel) et crée la dépense.
  Future<Expense> capture(String photoPath, ImageFilter filter) async {
    final id = const Uuid().v4();
    final original = await _files.saveOriginal(id, photoPath);
    final expense = Expense.draft(
      id: id,
      originalPath: original.path,
      filter: filter,
    );
    await _saveAndSync(expense);
    return expense;
  }

  Future<void> edit(Expense edited) async {
    final current = byId(edited.id);
    if (current == null) return;
    await _saveAndSync(current.withEditedFields(edited));
  }

  Future<void> reprocess(String id, ImageFilter filter) async {
    final current = byId(id);
    if (current == null) return;
    final pendingUpload = current.syncState == SyncState.pendingUpload;
    await _saveAndSync(
      current.copyWith(
        filter: filter,
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

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../domain/document.dart';
import '../../expense/domain/expense.dart';
import '../../scan/domain/quad.dart';
import '../../scan/domain/rotation.dart';
import '../../account/data/account_repository.dart';
import 'document_api.dart';
import 'document_sync_service.dart';
import '../../shared/data/file_store.dart';
import '../../shared/data/local_store.dart';
import '../../shared/data/sync_report.dart';

/// Page tout juste scannée : photo brute, contour choisi, filtre et rendu calculé sur l'appareil.
final class PageCapture {
  const PageCapture({
    required this.photoPath,
    required this.corners,
    required this.filter,
    this.rotation = Rotation.none,
    required this.processedJpeg,
  });

  final String photoPath;
  final Quad corners;
  final ImageFilter filter;
  final Rotation rotation;
  final List<int> processedJpeg;
}

/// Point d'entrée de l'UI pour les documents multi-pages : tout s'écrit d'abord sur l'appareil,
/// puis part vers le compte connecté (synchro rejouable, comme les dépenses).
class DocumentRepository extends ChangeNotifier {
  DocumentRepository({
    required this._store,
    required this._files,
    required http.Client httpClient,
    required this._account,
  }) : _wasConnected = _account.connected {
    _account.addListener(_onAccountChanged);
    _sync = DocumentSyncService(
      store: _store,
      api: DocumentApi(
        client: httpClient,
        settings: () => _account.settings,
        token: () => _account.session?.token,
      ),
      files: _files,
    );
  }

  final LocalStore _store;
  final FileStore _files;
  final AccountRepository _account;
  late final DocumentSyncService _sync;
  bool _wasConnected;
  Future<SyncReport?>? _running;
  bool _syncAgain = false;
  SyncReport? _lastReport;

  /// Synchronisation avec le serveur possible (adresse renseignée et compte connecté).
  bool get withServer => _account.connected;

  SyncReport? get lastReport => _lastReport;

  bool get isSyncing => _running != null;

  /// Lance une synchronisation ; un appel pendant une synchro en cours la fait rejouer à la fin.
  Future<SyncReport?> sync() {
    if (_running != null) {
      _syncAgain = true;
      return _running!;
    }
    if (!_account.connected) return Future.value(null);
    _running = _runSync();
    return _running!;
  }

  Future<SyncReport?> _runSync() async {
    try {
      do {
        _syncAgain = false;
        _lastReport = await _syncReportingFailures();
        await load();
      } while (_syncAgain && !_lastReport!.unauthorized);
    } finally {
      _running = null;
    }
    final report = _lastReport!;
    // Documents locaux conservés : ils repartiront à la prochaine connexion.
    if (report.unauthorized) await _account.expire();
    if (!report.offline &&
        !report.unauthorized &&
        (report.pushed > 0 || report.refusedForQuota > 0)) {
      await _account.refresh();
    }
    return report;
  }

  /// Une réponse inattendue du serveur ne fait jamais échouer l'action locale qui a lancé la
  /// synchro : elle est journalisée et rapportée ; tout sera rejoué à la synchro suivante.
  Future<SyncReport> _syncReportingFailures() async {
    try {
      return await _sync.sync();
    } on Object catch (e, st) {
      debugPrint('Synchronisation des documents impossible : $e\n$st');
      return SyncReport(errors: ['Synchronisation impossible : $e']);
    }
  }

  /// À la connexion (éventuellement à un autre compte), tout est récupéré et les documents locaux
  /// en attente partent vers le compte : l'envoi est idempotent (UUID du client). On ne se connecte
  /// qu'une fois déconnecté (la page Compte ne propose la connexion qu'alors) : tout changement de
  /// compte passe donc par ce front montant.
  Future<void> _onAccountChanged() async {
    final connected = _account.connected;
    final justConnected = connected && !_wasConnected;
    _wasConnected = connected;
    if (!justConnected) return;
    await _store.clearLastDocumentSync();
    await sync();
  }

  List<ScannedDocument> _all = const [];
  bool _disposed = false;

  /// Documents visibles (non supprimés), du plus récent au plus ancien.
  List<ScannedDocument> get documents =>
      List.unmodifiable(_all.where((d) => !d.deleted));

  ScannedDocument? byId(String id) {
    for (final d in _all) {
      if (d.id == id) return d;
    }
    return null;
  }

  Future<void> load() async {
    _all = await _store.documents();
    _notify();
  }

  Future<ScannedDocument> create(List<PageCapture> pages) async {
    final now = DateTime.now().toUtc();
    var doc = ScannedDocument.create(id: const Uuid().v4(), createdAt: now);
    for (final capture in pages) {
      doc = doc.withPage(await _savePage(capture), at: now);
    }
    await _save(doc);
    return doc;
  }

  /// Les fichiers des pages sont écrits d'abord ; le document est relu juste avant l'enregistrement
  /// pour ne pas écraser un changement fait entre-temps (renommage…).
  Future<void> addPages(String id, List<PageCapture> pages) async {
    if (byId(id) == null) return;
    final saved = [for (final capture in pages) await _savePage(capture)];
    await _update(
      id,
      (d, now) => saved.fold(d, (doc, page) => doc.withPage(page, at: now)),
    );
  }

  Future<void> removePage(String id, String pageId) =>
      _update(id, (d, now) => d.withoutPage(pageId, at: now));

  /// Nouveau rendu d'une page, calculé depuis son original (inchangé) ; l'ancien rendu est effacé
  /// une fois le document enregistré.
  Future<void> adjustPage(
    String id,
    String pageId, {
    required Quad corners,
    required ImageFilter filter,
    Rotation? rotation,
    required List<int> processedJpeg,
  }) async {
    final page = byId(id)?.pages.where((p) => p.id == pageId).firstOrNull;
    if (page == null) return;
    final processed = await _files.saveProcessedVersion(pageId, processedJpeg);
    await _update(
      id,
      (d, now) => d.withPageAdjusted(
        pageId,
        corners: corners,
        filter: filter,
        rotation: rotation,
        processedPath: processed.path,
        at: now,
      ),
    );
    // Seulement une fois la base à jour : la page ne pointe jamais vers un fichier effacé.
    await _files.deleteProcessed(pageId, page.processedPath);
  }

  Future<void> rename(String id, String title) =>
      _update(id, (d, now) => d.renamed(title, at: now));

  /// Suppression logique : le document et ses fichiers restent sur l'appareil.
  Future<void> delete(String id) =>
      _update(id, (d, now) => d.markDeleted(at: now));

  /// Copie la photo brute (jamais modifiée) et enregistre le rendu recadré, dans le dossier de la page.
  Future<ScannedPage> _savePage(PageCapture capture) async {
    final pageId = const Uuid().v4();
    final original = await _files.saveOriginal(pageId, capture.photoPath);
    final processed = await _files.saveProcessed(pageId, capture.processedJpeg);
    return ScannedPage(
      id: pageId,
      originalPath: original.path,
      processedPath: processed.path,
      corners: capture.corners,
      filter: capture.filter,
      rotation: capture.rotation,
    );
  }

  Future<void> _update(
    String id,
    ScannedDocument Function(ScannedDocument, DateTime) change,
  ) async {
    final doc = byId(id);
    if (doc == null) return;
    await _save(change(doc, DateTime.now().toUtc()));
  }

  Future<void> _save(ScannedDocument doc) async {
    await _store.saveDocument(doc);
    await load();
    await sync();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _account.removeListener(_onAccountChanged);
    _disposed = true;
    super.dispose();
  }
}

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../domain/document.dart';
import '../domain/expense.dart';
import '../domain/quad.dart';
import 'file_store.dart';
import 'local_store.dart';

/// Page tout juste scannée : photo brute, contour choisi, filtre et rendu calculé sur l'appareil.
final class PageCapture {
  const PageCapture({
    required this.photoPath,
    required this.corners,
    required this.filter,
    required this.processedJpeg,
  });

  final String photoPath;
  final Quad corners;
  final ImageFilter filter;
  final List<int> processedJpeg;
}

/// Point d'entrée de l'UI pour les documents multi-pages, stockés sur l'appareil uniquement.
class DocumentRepository extends ChangeNotifier {
  DocumentRepository({required this._store, required this._files});

  final LocalStore _store;
  final FileStore _files;

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
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

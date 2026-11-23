import 'dart:io';

import '../domain/document.dart';
import '../domain/expense.dart';
import '../domain/quad.dart';
import 'document_api.dart';
import 'file_store.dart';
import 'image_types.dart';
import 'local_store.dart';
import 'sync_service.dart';

/// Synchronisation rejouable des documents, sur le modèle de celle des dépenses : les changements
/// locaux partent d'abord (l'appareil fait foi tant qu'ils ne sont pas envoyés), puis les
/// changements du serveur sont reçus avec leurs fichiers.
final class DocumentSyncService {
  DocumentSyncService({
    required this._store,
    required this._api,
    required this._files,
  });

  final LocalStore _store;
  final DocumentApi _api;
  final FileStore _files;

  /// Marge pour ne manquer aucune modification faite à la même milliseconde.
  static const _overlap = Duration(seconds: 1);

  Future<SyncReport> sync() async {
    var pushed = 0, pulled = 0, refusedForQuota = 0;
    final errors = <String>[];
    SyncReport report({bool offline = false, bool unauthorized = false}) =>
        SyncReport(
          pushed: pushed,
          pulled: pulled,
          errors: errors,
          offline: offline,
          unauthorized: unauthorized,
          refusedForQuota: refusedForQuota,
        );
    try {
      for (final local in await _store.pendingDocuments()) {
        try {
          await _push(local);
          pushed++;
        } on QuotaExceededException {
          refusedForQuota++; // reste en attente d'envoi : retenté à la prochaine synchro
        } on ApiException catch (e) {
          errors.add('${local.id} : $e');
        } on FileSystemException catch (e) {
          // Rendu remplacé pendant l'envoi : le document repartira avec ses fichiers actuels.
          errors.add('${local.id} : $e');
        }
      }
      pulled = await _pull(errors);
    } on FormatException catch (e) {
      errors.add('Réponse du serveur illisible : $e');
      return report();
    } on OfflineException {
      return report(offline: true);
    } on UnauthorizedException {
      return report(unauthorized: true);
    }
    return report();
  }

  /// Titre et ordre d'abord (le serveur connaît ainsi la place des pages à venir), puis les pages
  /// non envoyées ou réajustées. Le document n'est marqué envoyé que s'il n'a pas changé entre-temps.
  Future<void> _push(ScannedDocument doc) async {
    if (doc.syncState == SyncState.pendingDelete) {
      await _api.delete(doc.id);
    } else {
      await _api.save(doc);
      for (final page in doc.pages) {
        await _pushPage(doc.id, page);
      }
    }
    await _store.markDocumentSynced(doc.id, updatedAt: doc.updatedAt);
  }

  Future<void> _pushPage(String documentId, ScannedPage page) async {
    final int version;
    switch (page.syncState) {
      case SyncState.pendingUpload:
        version = await _api.uploadPage(
          documentId,
          page,
          original: await File(page.originalPath).readAsBytes(),
          originalContentType: contentTypeOfPath(page.originalPath),
          processed: await File(page.processedPath).readAsBytes(),
        );
      case SyncState.pendingReprocess:
        version = await _api.replaceRender(
          documentId,
          page,
          await File(page.processedPath).readAsBytes(),
        );
      default:
        return;
    }
    await _store.markPageSynced(
      page.id,
      processedPath: page.processedPath,
      renderVersion: version,
    );
  }

  Future<int> _pull(List<String> errors) async {
    final lastSync = await _store.lastDocumentSync();
    final changes = await _api.changesSince(lastSync?.subtract(_overlap));
    var newest = lastSync;
    DateTime? firstFailure;
    var pulled = 0;
    for (final remote in changes) {
      final local = await _store.document(remote.id);
      if (local != null && local.syncState != SyncState.synced) {
        continue; // changement local en attente
      }
      try {
        if (await _receive(remote, local)) pulled++;
      } on Exception catch (e) {
        // ApiException (téléchargement refusé), FileSystemException… : reçu à la synchro suivante.
        errors.add('${remote.id} : $e');
        if (firstFailure == null || remote.updatedAt.isBefore(firstFailure)) {
          firstFailure = remote.updatedAt;
        }
      }
      if (newest == null || remote.updatedAt.isAfter(newest)) {
        newest = remote.updatedAt;
      }
    }
    // Un document non reçu doit revenir dans les changements de la synchro suivante.
    if (firstFailure != null && newest!.isAfter(firstFailure)) {
      newest = firstFailure.subtract(_overlap);
    }
    if (newest != null) await _store.setLastDocumentSync(newest);
    return pulled;
  }

  /// Enregistre l'état du serveur ; rend `false` s'il n'y avait rien à changer (supprimé inconnu,
  /// retour d'un envoi de cet appareil) ou si l'appareil a changé le document entre-temps.
  Future<bool> _receive(RemoteDocument remote, ScannedDocument? local) async {
    if (remote.deleted && (local == null || local.deleted)) return false;
    if (!remote.deleted && _alreadyUpToDate(remote, local)) return false;
    final pages = remote.deleted
        ? local!.pages
        : [
            for (final page in remote.pages)
              await _withFiles(remote.id, page, local),
          ];
    final saved = await _store.saveReceivedDocument(
      _synced(remote, local, pages),
      readUpdatedAt: local?.updatedAt,
    );
    if (!saved) return false;
    // Seulement une fois la base à jour : une page ne pointe jamais vers un fichier effacé.
    for (final old in local?.pages ?? const <ScannedPage>[]) {
      final current = pages.where((p) => p.id == old.id).firstOrNull;
      if (current != null && current.processedPath != old.processedPath) {
        await _files.deleteProcessed(old.id, old.processedPath);
      }
    }
    return true;
  }

  /// Même titre, mêmes pages dans le même ordre et mêmes rendus : rien à réécrire.
  static bool _alreadyUpToDate(RemoteDocument remote, ScannedDocument? local) {
    if (local == null || local.deleted || local.title != remote.title) {
      return false;
    }
    if (local.pages.length != remote.pages.length) return false;
    for (final (i, page) in remote.pages.indexed) {
      final known = local.pages[i];
      if (known.id != page.id || known.renderVersion != page.renderVersion) {
        return false;
      }
    }
    return true;
  }

  /// Télécharge ce qui manque : l'original d'une page nouvelle sur l'appareil, et le rendu quand
  /// sa version a changé.
  Future<ScannedPage> _withFiles(
    String documentId,
    RemotePage remote,
    ScannedDocument? local,
  ) async {
    final known = local?.pages.where((p) => p.id == remote.id).firstOrNull;
    final originalPath =
        known?.originalPath ?? await _downloadOriginal(documentId, remote.id);
    final processedPath = known?.renderVersion == remote.renderVersion
        ? known!.processedPath
        : (await _files.saveProcessedVersion(
            remote.id,
            await _api.processedImage(documentId, remote.id),
          )).path;
    return ScannedPage(
      id: remote.id,
      originalPath: originalPath,
      processedPath: processedPath,
      corners: remote.corners ?? Quad.inset(0),
      filter: remote.filter,
      syncState: SyncState.synced,
      renderVersion: remote.renderVersion,
    );
  }

  /// Un original déjà présent (téléchargement interrompu avant l'enregistrement) est gardé tel quel.
  Future<String> _downloadOriginal(String documentId, String pageId) async {
    final original = await _api.originalImage(documentId, pageId);
    final extension = extensionOfContentType(original.contentType);
    final existing = _files.originalFile(pageId, extension);
    if (await existing.exists()) return existing.path;
    return (await _files.saveOriginalBytes(
      pageId,
      original.bytes,
      extension,
    )).path;
  }

  static ScannedDocument _synced(
    RemoteDocument remote,
    ScannedDocument? local,
    List<ScannedPage> pages,
  ) => ScannedDocument(
    id: remote.id,
    title: remote.title,
    createdAt: local?.createdAt ?? remote.createdAt,
    updatedAt: remote.updatedAt,
    pages: pages,
    deleted: remote.deleted,
    syncState: SyncState.synced,
  );
}

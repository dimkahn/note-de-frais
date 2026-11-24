import '../../expense/domain/expense.dart';
import '../../scan/domain/quad.dart';

/// Page scannée : photo brute conservée telle quelle et copie recadrée/filtrée.
final class ScannedPage {
  const ScannedPage({
    required this.id,
    required this.originalPath,
    required this.processedPath,
    required this.corners,
    required this.filter,
    this.syncState = SyncState.pendingUpload,
    this.renderVersion,
  });

  final String id;
  final String originalPath;
  final String processedPath;
  final Quad corners;
  final ImageFilter filter;

  /// `pendingUpload` (jamais envoyée), `pendingReprocess` (rendu à renvoyer) ou `synced`.
  final SyncState syncState;

  /// Version du rendu connue du serveur (`null` : jamais envoyée).
  final int? renderVersion;
}

/// Document de plusieurs pages (contrat, attestation…), distinct d'une dépense. Immuable.
final class ScannedDocument {
  ScannedDocument({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    List<ScannedPage> pages = const [],
    this.deleted = false,
    this.syncState = SyncState.pendingUpload,
  }) : pages = List.unmodifiable(pages);

  factory ScannedDocument.create({
    required String id,
    required DateTime createdAt,
  }) {
    final d = createdAt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return ScannedDocument(
      id: id,
      title: 'Document du ${two(d.day)}/${two(d.month)}/${d.year}',
      createdAt: createdAt,
      updatedAt: createdAt,
    );
  }

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ScannedPage> pages;
  final bool deleted;

  /// État d'envoi au serveur du document (titre, ordre des pages, suppression).
  final SyncState syncState;

  /// Première page, utilisée comme vignette.
  ScannedPage? get cover => pages.isEmpty ? null : pages.first;

  ScannedDocument withPage(ScannedPage page, {required DateTime at}) =>
      _copy(pages: [...pages, page], updatedAt: at);

  /// Retire la page de la liste ; ses fichiers (dont l'original) restent sur l'appareil.
  ScannedDocument withoutPage(String pageId, {required DateTime at}) => _copy(
    pages: [
      for (final p in pages)
        if (p.id != pageId) p,
    ],
    updatedAt: at,
  );

  /// Nouveau rendu d'une page à partir de son original, qui ne change pas ; la page garde sa place.
  ScannedDocument withPageAdjusted(
    String pageId, {
    required Quad corners,
    required ImageFilter filter,
    required String processedPath,
    required DateTime at,
  }) => _copy(
    pages: [
      for (final p in pages)
        p.id == pageId
            ? ScannedPage(
                id: p.id,
                originalPath: p.originalPath,
                processedPath: processedPath,
                corners: corners,
                filter: filter,
                // Jamais envoyée : partira avec son rendu courant.
                syncState: p.syncState == SyncState.pendingUpload
                    ? SyncState.pendingUpload
                    : SyncState.pendingReprocess,
                renderVersion: p.renderVersion,
              )
            : p,
    ],
    updatedAt: at,
  );

  ScannedDocument renamed(String title, {required DateTime at}) {
    final trimmed = title.trim();
    return trimmed.isEmpty ? this : _copy(title: trimmed, updatedAt: at);
  }

  ScannedDocument markDeleted({required DateTime at}) =>
      _copy(deleted: true, updatedAt: at, syncState: SyncState.pendingDelete);

  ScannedDocument _copy({
    String? title,
    List<ScannedPage>? pages,
    bool? deleted,
    required DateTime updatedAt,
    SyncState? syncState,
  }) => ScannedDocument(
    id: id,
    title: title ?? this.title,
    createdAt: createdAt,
    updatedAt: updatedAt,
    pages: pages ?? this.pages,
    deleted: deleted ?? this.deleted,
    // Un document jamais envoyé le sera avec son état courant.
    syncState:
        syncState ??
        (this.syncState == SyncState.pendingUpload
            ? SyncState.pendingUpload
            : SyncState.pendingUpdate),
  );
}

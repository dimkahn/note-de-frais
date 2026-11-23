import 'expense.dart';
import 'quad.dart';

/// Page scannée : photo brute conservée telle quelle et copie recadrée/filtrée.
final class ScannedPage {
  const ScannedPage({
    required this.id,
    required this.originalPath,
    required this.processedPath,
    required this.corners,
    required this.filter,
  });

  final String id;
  final String originalPath;
  final String processedPath;
  final Quad corners;
  final ImageFilter filter;
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

  ScannedDocument renamed(String title, {required DateTime at}) {
    final trimmed = title.trim();
    return trimmed.isEmpty ? this : _copy(title: trimmed, updatedAt: at);
  }

  ScannedDocument markDeleted({required DateTime at}) =>
      _copy(deleted: true, updatedAt: at);

  ScannedDocument _copy({
    String? title,
    List<ScannedPage>? pages,
    bool? deleted,
    required DateTime updatedAt,
  }) => ScannedDocument(
    id: id,
    title: title ?? this.title,
    createdAt: createdAt,
    updatedAt: updatedAt,
    pages: pages ?? this.pages,
    deleted: deleted ?? this.deleted,
  );
}

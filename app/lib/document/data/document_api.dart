import 'package:http/http.dart' as http;

import '../domain/document.dart';
import '../../expense/domain/expense.dart';
import '../../scan/domain/quad.dart';
import '../../shared/data/server_client.dart';

export '../../shared/data/server_client.dart'
    show
        ApiException,
        OfflineException,
        QuotaExceededException,
        ServerSettings,
        UnauthorizedException;

/// Page telle que le serveur la décrit.
final class RemotePage {
  const RemotePage({
    required this.id,
    required this.filter,
    required this.corners,
    required this.renderVersion,
  });

  factory RemotePage.fromJson(Map<String, Object?> json) {
    final corners = json['corners'] as String?;
    return RemotePage(
      id: json['id']! as String,
      filter: ImageFilter.fromCode(json['filter'] as String?),
      corners: corners == null ? null : Quad.parse(corners),
      renderVersion: json['renderVersion']! as int,
    );
  }

  final String id;
  final ImageFilter filter;
  final Quad? corners;
  final int renderVersion;
}

/// Document tel que le serveur le décrit : pages reçues, dans l'ordre.
final class RemoteDocument {
  const RemoteDocument({
    required this.id,
    required this.title,
    required this.pages,
    required this.deleted,
    required this.createdAt,
    required this.updatedAt,
  });

  factory RemoteDocument.fromJson(Map<String, Object?> json) => RemoteDocument(
    id: json['id']! as String,
    title: json['title']! as String,
    pages: (json['pages']! as List)
        .cast<Map<String, Object?>>()
        .map(RemotePage.fromJson)
        .toList(),
    deleted: json['deleted'] == true,
    createdAt: DateTime.parse(json['createdAt']! as String),
    updatedAt: DateTime.parse(json['updatedAt']! as String),
  );

  final String id;
  final String title;
  final List<RemotePage> pages;
  final bool deleted;
  final DateTime createdAt;
  final DateTime updatedAt;
}

/// Client de l'API REST `/api/documents`.
final class DocumentApi {
  DocumentApi({
    required http.Client client,
    required ServerSettings Function() settings,
    required String? Function() token,
  }) : _server = ServerClient(client: client, settings: settings, token: token);

  final ServerClient _server;

  /// Crée ou met à jour le document : titre et ordre complet des pages de l'appareil.
  Future<RemoteDocument> save(ScannedDocument doc) async => _document(
    await _server.putJson('/api/documents/${doc.id}', {
      'title': doc.title,
      'pageIds': [for (final p in doc.pages) p.id],
    }),
  );

  /// Envoie une page (idempotent) ; rend la version du rendu connue du serveur.
  Future<int> uploadPage(
    String documentId,
    ScannedPage page, {
    required List<int> original,
    required String originalContentType,
    required List<int> processed,
  }) async => _renderVersion(
    await _server.multipart(
      '/api/documents/$documentId/pages',
      (request) => request
        ..fields['pageId'] = page.id
        ..fields.addAll(_rendering(page))
        ..files.add(
          ServerClient.file('original', original, originalContentType),
        )
        ..files.add(ServerClient.file('processed', processed, 'image/jpeg')),
    ),
  );

  /// Remplace le rendu d'une page réajustée ; rend la nouvelle version.
  Future<int> replaceRender(
    String documentId,
    ScannedPage page,
    List<int> processed,
  ) async => _renderVersion(
    await _server.multipart(
      '/api/documents/$documentId/pages/${page.id}/processed',
      (request) => request
        ..fields.addAll(_rendering(page))
        ..files.add(ServerClient.file('processed', processed, 'image/jpeg')),
    ),
  );

  /// Supprime côté serveur ; un document déjà absent est considéré comme supprimé.
  Future<void> delete(String id) => _server.delete('/api/documents/$id');

  Future<List<RemoteDocument>> changesSince(DateTime? since) async {
    final from = since ?? DateTime.utc(1970);
    final response = await _server.get('/api/documents/changes', {
      'since': from.toUtc().toIso8601String(),
    });
    return (ServerClient.json(response) as List)
        .cast<Map<String, Object?>>()
        .map(RemoteDocument.fromJson)
        .toList();
  }

  Future<({List<int> bytes, String contentType})> originalImage(
    String documentId,
    String pageId,
  ) async {
    final response = await _server.get(
      '/api/documents/$documentId/pages/$pageId/original',
    );
    return (
      bytes: response.bodyBytes,
      contentType: response.headers['content-type'] ?? 'image/jpeg',
    );
  }

  Future<List<int>> processedImage(String documentId, String pageId) async =>
      (await _server.get('/api/documents/$documentId/pages/$pageId/processed'))
          .bodyBytes;

  static Map<String, String> _rendering(ScannedPage page) => {
    'filter': page.filter.code,
    'corners': page.corners.format(),
  };

  static RemoteDocument _document(http.Response response) =>
      RemoteDocument.fromJson(
        ServerClient.json(response) as Map<String, Object?>,
      );

  static int _renderVersion(http.Response response) =>
      (ServerClient.json(response) as Map<String, Object?>)['renderVersion']!
          as int;
}

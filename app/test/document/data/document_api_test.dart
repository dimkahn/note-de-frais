import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_de_frais/document/data/document_api.dart';
import 'package:note_de_frais/document/domain/document.dart';
import 'package:note_de_frais/expense/domain/expense.dart';
import 'package:note_de_frais/scan/domain/quad.dart';

import '../../support/fake_server.dart';

void main() {
  late FakeServer server;
  late DocumentApi api;
  final at = DateTime.utc(2026, 11, 23, 9);

  ScannedPage page(String id) => ScannedPage(
    id: id,
    originalPath: '/docs/$id/original.png',
    processedPath: '/docs/$id/processed.jpg',
    corners: Quad.inset(0.1),
    filter: ImageFilter.scanBw,
  );

  ScannedDocument doc() => ScannedDocument(
    id: 'd1',
    title: 'Bail',
    createdAt: at,
    updatedAt: at,
    pages: [page('p1'), page('p2')],
  );

  setUp(() {
    server = FakeServer();
    api = DocumentApi(
      client: server.client,
      settings: () => const ServerSettings(baseUrl: 'http://serveur/'),
      token: () => 'jeton',
    );
  });

  test(
    'enregistre le titre et l\'ordre des pages avec le jeton de session',
    () async {
      await api.save(doc());

      final put = server.requests.single;
      expect(put.method, 'PUT');
      expect(put.url.toString(), 'http://serveur/api/documents/d1');
      expect(put.headers['Authorization'], 'Bearer jeton');
      expect(jsonDecode(put.body), {
        'title': 'Bail',
        'pageIds': ['p1', 'p2'],
      });
    },
  );

  test(
    'envoie une page avec son original, son rendu, son filtre et son contour',
    () async {
      await api.save(doc());

      final version = await api.uploadPage(
        'd1',
        page('p1'),
        original: [1, 2],
        originalContentType: 'image/png',
        processed: [3],
      );

      expect(version, 1);
      final upload = server.requests.last;
      final body = utf8.decode(upload.bodyBytes, allowMalformed: true);
      expect(upload.url.path, '/api/documents/d1/pages');
      expect(body, contains('name="pageId"\r\n\r\np1'));
      expect(body, contains('name="filter"\r\n\r\nSCAN_BW'));
      expect(
        body,
        contains('name="corners"\r\n\r\n${Quad.inset(0.1).format()}'),
      );
      expect(body, contains('name="original"'));
      expect(body, contains('content-type: image/png'));
      expect(body, contains('name="processed"'));
    },
  );

  test('un nouveau rendu rend la nouvelle version du serveur', () async {
    await api.save(doc());
    await api.uploadPage(
      'd1',
      page('p1'),
      original: [1],
      originalContentType: 'image/jpeg',
      processed: [2],
    );

    final version = await api.replaceRender('d1', page('p1'), [4]);

    expect(version, 2);
    expect(
      server.requests.last.url.path,
      '/api/documents/d1/pages/p1/processed',
    );
  });

  test(
    'une page refusée faute d\'espace lève QuotaExceededException',
    () async {
      await api.save(doc());
      server.quotaFull = true;

      expect(
        api.uploadPage(
          'd1',
          page('p1'),
          original: [1],
          originalContentType: 'image/jpeg',
          processed: [2],
        ),
        throwsA(isA<QuotaExceededException>()),
      );
    },
  );

  test(
    'lit les changements : titre, pages dans l\'ordre, suppression',
    () async {
      server.documentFromAnotherDevice('d9', ['b', 'a']);

      final changes = await api.changesSince(null);

      final remote = changes.single;
      expect(remote.id, 'd9');
      expect(remote.title, 'Venu d\'ailleurs');
      expect(remote.deleted, isFalse);
      expect(remote.pages.map((p) => p.id), ['b', 'a']);
      expect(remote.pages.first.filter, ImageFilter.scanBw);
      expect(
        remote.pages.first.corners,
        Quad.parse('0.1,0.1,0.9,0.1,0.9,0.9,0.1,0.9'),
      );
      expect(remote.pages.first.renderVersion, 1);
      expect(remote.createdAt, DateTime.utc(2026, 11, 23, 9));
      expect(
        server.requests.single.url.queryParameters['since'],
        '1970-01-01T00:00:00.000Z',
      );
    },
  );

  test('la suppression d\'un document absent du serveur réussit', () async {
    await api.delete('inconnu');

    expect(server.requests.single.method, 'DELETE');
  });

  test(
    'télécharge l\'original avec son type et le rendu d\'une page',
    () async {
      server.documentFromAnotherDevice('d9', ['a']);

      final original = await api.originalImage('d9', 'a');
      final processed = await api.processedImage('d9', 'a');

      expect(original.bytes, [1, 1]);
      expect(original.contentType, 'image/png');
      expect(processed, [7, 1]);
    },
  );
}

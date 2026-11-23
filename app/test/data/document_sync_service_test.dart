import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_de_frais/data/document_api.dart';
import 'package:note_de_frais/data/document_sync_service.dart';
import 'package:note_de_frais/data/file_store.dart';
import 'package:note_de_frais/data/local_store.dart';
import 'package:note_de_frais/domain/document.dart';
import 'package:note_de_frais/domain/expense.dart';
import 'package:note_de_frais/domain/quad.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/fake_server.dart';

void main() {
  sqfliteFfiInit();
  late Directory dir;
  late LocalStore store;
  late FileStore files;
  late FakeServer server;
  late DocumentSyncService sync;
  final at = DateTime.utc(2026, 11, 23, 9);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ndf_doc_sync');
    store = await LocalStore.open(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    files = FileStore(dir);
    server = FakeServer();
    sync = DocumentSyncService(
      store: store,
      api: DocumentApi(
        client: server.client,
        settings: () => const ServerSettings(baseUrl: 'http://serveur'),
        token: () => 'jeton',
      ),
      files: files,
    );
  });

  tearDown(() async {
    await store.close();
    await dir.delete(recursive: true);
  });

  Future<ScannedPage> scannedPage(String id) async {
    final source = File('${dir.path}/$id.jpg')..writeAsBytesSync([1, 2, 3]);
    return ScannedPage(
      id: id,
      originalPath: (await files.saveOriginal(id, source.path)).path,
      processedPath: (await files.saveProcessed(id, [9])).path,
      corners: Quad.inset(0.1),
      filter: ImageFilter.scanBw,
    );
  }

  Future<ScannedDocument> scanned(String id, List<String> pageIds) async {
    var doc = ScannedDocument.create(id: id, createdAt: at);
    for (final pageId in pageIds) {
      doc = doc.withPage(await scannedPage(pageId), at: at);
    }
    await store.saveDocument(doc);
    return doc;
  }

  Future<ScannedDocument> local(String id) async => (await store.document(id))!;

  List<String> requestsTo(String pathEnd) => [
    for (final r in server.requests)
      if (r.url.path.endsWith(pathEnd)) '${r.method} ${r.url.path}',
  ];

  test('envoie un nouveau document puis chacune de ses pages', () async {
    await scanned('d1', ['p1', 'p2']);

    final report = await sync.sync();

    expect(report.pushed, 1);
    expect(server.documents['d1']!.title, startsWith('Document du'));
    expect(server.documents['d1']!.pages.keys, ['p1', 'p2']);
    final doc = await local('d1');
    expect(doc.syncState, SyncState.synced);
    expect(doc.pages.map((p) => p.syncState), everyElement(SyncState.synced));
    expect(doc.pages.first.renderVersion, 1);
  });

  test('hors-ligne, le document reste en attente et repart ensuite', () async {
    await scanned('d1', ['p1']);
    server.offline = true;

    final report = await sync.sync();

    expect(report.offline, isTrue);
    expect((await local('d1')).syncState, SyncState.pendingUpload);
    server.offline = false;
    await sync.sync();
    expect((await local('d1')).syncState, SyncState.synced);
  });

  test('faute d\'espace en ligne, le document reste sur l\'appareil et est retenté', () async {
    await scanned('d1', ['p1']);
    server.quotaFull = true;

    final refused = await sync.sync();

    expect(refused.refusedForQuota, 1);
    expect(refused.pushed, 0);
    expect((await local('d1')).syncState, SyncState.pendingUpload);
    expect((await local('d1')).pages.single.syncState, SyncState.pendingUpload);
    server.quotaFull = false;
    final retried = await sync.sync();
    expect(retried.refusedForQuota, 0);
    expect((await local('d1')).syncState, SyncState.synced);
  });

  test('une page réajustée n\'envoie que son nouveau rendu', () async {
    await scanned('d1', ['p1']);
    await sync.sync();
    final sent = await local('d1');
    final rendered = await files.saveProcessedVersion('p1', [8]);
    await store.saveDocument(
      sent.withPageAdjusted(
        'p1',
        corners: Quad.inset(0.2),
        filter: ImageFilter.sharpen,
        processedPath: rendered.path,
        at: at.add(const Duration(minutes: 1)),
      ),
    );

    await sync.sync();

    expect(requestsTo('/pages'), hasLength(1));
    expect(requestsTo('/p1/processed'), [
      'POST /api/documents/d1/pages/p1/processed',
    ]);
    final page = (await local('d1')).pages.single;
    expect(page.syncState, SyncState.synced);
    expect(page.renderVersion, 2);
  });

  test('un retrait de page envoie le nouvel ordre au serveur', () async {
    await scanned('d1', ['p1', 'p2']);
    await sync.sync();

    await store.saveDocument(
      (await local('d1'))
          .withoutPage('p1', at: at.add(const Duration(minutes: 1))),
    );
    await sync.sync();

    expect(server.documents['d1']!.pageOrder, ['p2']);
    expect((await local('d1')).pages.map((p) => p.id), ['p2']);
  });

  test('propage la suppression d\'un document', () async {
    await scanned('d1', ['p1']);
    await sync.sync();
    await store.saveDocument(
      (await local('d1')).markDeleted(at: at.add(const Duration(minutes: 1))),
    );

    await sync.sync();

    expect(server.documents['d1']!.deleted, isTrue);
    expect((await local('d1')).syncState, SyncState.synced);
  });

  test('reçoit un document d\'un autre appareil avec ses fichiers', () async {
    server.documentFromAnotherDevice('d9', ['b', 'a']);

    final report = await sync.sync();

    expect(report.pulled, 1);
    final doc = await local('d9');
    expect(doc.title, 'Venu d\'ailleurs');
    expect(doc.syncState, SyncState.synced);
    expect(doc.pages.map((p) => p.id), ['b', 'a']);
    expect(await File(doc.pages.first.originalPath).readAsBytes(), [1, 1]);
    expect(await File(doc.pages.first.processedPath).readAsBytes(), [7, 1]);
    expect(doc.pages.first.filter, ImageFilter.scanBw);
    expect(doc.pages.first.syncState, SyncState.synced);
    expect(doc.pages.first.renderVersion, 1);
  });

  test(
    'retélécharge un rendu refait ailleurs, sans toucher à l\'original',
    () async {
      server.documentFromAnotherDevice('d9', ['a']);
      await sync.sync();
      final before = (await local('d9')).pages.single;
      server.rerenderedElsewhere('d9', 'a');

      await sync.sync();

      final after = (await local('d9')).pages.single;
      expect(after.renderVersion, 2);
      expect(await File(after.processedPath).readAsBytes(), [7, 2]);
      expect(File(before.processedPath).existsSync(), isFalse);
      expect(after.originalPath, before.originalPath);
      expect(await File(after.originalPath).readAsBytes(), [1, 1]);
      expect(requestsTo('/original'), hasLength(1));
    },
  );

  test(
    'ne retélécharge pas les fichiers d\'un document envoyé par cet appareil',
    () async {
      await scanned('d1', ['p1']);

      await sync.sync();
      await sync.sync();

      expect(requestsTo('/original'), isEmpty);
      expect(
        requestsTo('/processed').where((r) => r.startsWith('GET')),
        isEmpty,
      );
      expect(
        await File((await local('d1')).pages.single.processedPath)
            .readAsBytes(),
        [9],
      );
    },
  );

  test(
    'un changement local en attente n\'est pas écrasé par le serveur',
    () async {
      server.documentFromAnotherDevice('d9', ['a']);
      await sync.sync();
      await store.saveDocument(
        (await local('d9'))
            .renamed('Local', at: at.add(const Duration(days: 1))),
      );
      server.offline = true;
      await sync.sync();
      server.offline = false;
      server.documents['d9']!.title = 'Serveur';

      await sync.sync();

      expect(server.documents['d9']!.title, 'Local');
      expect((await local('d9')).title, 'Local');
    },
  );

  test(
    'une suppression faite ailleurs est appliquée sur l\'appareil',
    () async {
      server.documentFromAnotherDevice('d9', ['a']);
      await sync.sync();
      server.documents['d9']!
        ..deleted = true
        ..updatedAt = DateTime.utc(2027);

      await sync.sync();

      expect((await local('d9')).deleted, isTrue);
      expect(
        File((await local('d9')).pages.single.originalPath).existsSync(),
        isTrue,
      );
    },
  );

  test('une session refusée interrompt la synchro sans rien perdre', () async {
    await scanned('d1', ['p1']);
    server.expireSessions();

    final report = await sync.sync();

    expect(report.unauthorized, isTrue);
    expect((await local('d1')).syncState, SyncState.pendingUpload);
  });

  test('un fichier de page disparu laisse le document en attente sans bloquer les autres', () async {
    final broken = await scanned('d1', ['p1']);
    await File(broken.pages.single.processedPath).delete();
    await scanned('d2', ['p2']);

    final report = await sync.sync();

    expect(report.errors, hasLength(1));
    expect((await local('d1')).syncState, SyncState.pendingUpload);
    expect((await local('d2')).syncState, SyncState.synced);
  });

  test(
    'un document dont la réception a échoué est reçu à la synchro suivante',
    () async {
      server.documentFromAnotherDevice('d9', ['a']);
      server.pageOriginalsFail = true;
      server.documentFromAnotherDevice('d10', []).updatedAt = DateTime.utc(
        2027,
      );

      final failed = await sync.sync();
      server.pageOriginalsFail = false;
      await sync.sync();

      expect(failed.errors, hasLength(1));
      expect((await store.document('d9'))?.pages.single.id, 'a');
    },
  );

  test(
    'une modification locale faite pendant la réception n\'est pas écrasée',
    () async {
      server.documentFromAnotherDevice('d9', ['a']);
      await sync.sync();
      server.rerenderedElsewhere('d9', 'a');
      server.beforePageOriginal = null;
      server.documents['d9']!.title = 'Serveur';
      var renamed = false;
      server.beforeProcessedDownload = () async {
        if (renamed) return;
        renamed = true;
        await store.saveDocument(
          (await local('d9')).renamed('Local', at: DateTime.utc(2030)),
        );
      };

      await sync.sync();

      expect((await local('d9')).title, 'Local');
      expect((await local('d9')).syncState, SyncState.pendingUpdate);
    },
  );

  test(
    'le retour d\'un document envoyé par cet appareil n\'est pas compté reçu',
    () async {
      await scanned('d1', ['p1']);

      final report = await sync.sync();

      expect(report.pushed, 1);
      expect(report.pulled, 0);
    },
  );

  test('la suppression d\'un document jamais envoyé aboutit', () async {
    await store.saveDocument(
      ScannedDocument.create(id: 'd1', createdAt: at).markDeleted(at: at),
    );

    final report = await sync.sync();

    expect(report.errors, isEmpty);
    expect((await local('d1')).syncState, SyncState.synced);
  });

  test(
    'un corps de réponse illisible est rapporté sans interrompre l\'app',
    () async {
      await scanned('d1', ['p1']);
      server.documentChangesBody = '<html>';

      final report = await sync.sync();

      expect(report.errors, isNotEmpty);
      expect((await local('d1')).syncState, SyncState.synced);
    },
  );
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_de_frais/data/account_repository.dart';
import 'package:note_de_frais/data/document_repository.dart';
import 'package:note_de_frais/data/file_store.dart';
import 'package:note_de_frais/data/local_store.dart';
import 'package:note_de_frais/domain/expense.dart';
import 'package:note_de_frais/domain/quad.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/fake_biometric_auth.dart';
import '../support/fake_server.dart';
import '../support/memory_device_key_store.dart';
import '../support/memory_session_store.dart';

void main() {
  sqfliteFfiInit();
  late Directory dir;
  late LocalStore store;
  late FakeServer server;
  late MemorySessionStore sessions;
  late AccountRepository account;
  late DocumentRepository repo;

  DocumentRepository documents() => DocumentRepository(
    store: store,
    files: FileStore(dir),
    httpClient: server.client,
    account: account,
  );

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ndf_docs');
    store = await LocalStore.open(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    server = FakeServer();
    // Sans compte par défaut : les documents restent sur l'appareil.
    sessions = MemorySessionStore();
    account = AccountRepository(
      store: store,
      sessions: sessions,
      deviceKeys: MemoryDeviceKeyStore(),
      biometrics: FakeBiometricAuth(available: false),
      httpClient: server.client,
    );
    await account.load();
    await account.saveServerAddress('http://serveur');
    repo = documents();
    await repo.load();
  });

  tearDown(() async {
    repo.dispose();
    account.dispose();
    await store.close();
    await dir.delete(recursive: true);
  });

  PageCapture capture(List<int> photo, {List<int> processed = const [9]}) =>
      PageCapture(
        photoPath: (File(
          '${dir.path}/photo-${photo.first}.jpg',
        )..writeAsBytesSync(photo)).path,
        corners: Quad.inset(0.1),
        filter: ImageFilter.scanBw,
        processedJpeg: processed,
      );

  test(
    'crée un document avec ses pages, originaux copiés tels quels',
    () async {
      final doc = await repo.create([
        capture([1]),
        capture([2]),
      ]);

      expect(repo.documents.map((d) => d.id), [doc.id]);
      expect(doc.pages, hasLength(2));
      expect(await File(doc.pages[0].originalPath).readAsBytes(), [1]);
      expect(await File(doc.pages[1].originalPath).readAsBytes(), [2]);
      expect(await File(doc.pages[0].processedPath).readAsBytes(), [9]);
      expect(doc.pages[0].filter, ImageFilter.scanBw);
    },
  );

  test('ajoute des pages à la fin d\'un document existant', () async {
    final doc = await repo.create([
      capture([1]),
    ]);

    await repo.addPages(doc.id, [
      capture([3]),
    ]);

    final pages = repo.byId(doc.id)!.pages;
    expect(pages, hasLength(2));
    expect(await File(pages.last.originalPath).readAsBytes(), [3]);
  });

  test('retire une page en conservant son original sur l\'appareil', () async {
    final doc = await repo.create([
      capture([1]),
      capture([2]),
    ]);
    final removed = doc.pages.first;

    await repo.removePage(doc.id, removed.id);

    expect(repo.byId(doc.id)!.pages.map((p) => p.id), [doc.pages.last.id]);
    expect(File(removed.originalPath).existsSync(), isTrue);
  });

  test(
    'réajuste une page : nouveau rendu, original intact, ancien rendu effacé',
    () async {
      final doc = await repo.create([
        capture([1], processed: [9]),
        capture([2]),
      ]);
      final before = doc.pages.first;

      await repo.adjustPage(
        doc.id,
        before.id,
        corners: Quad.inset(0.2),
        filter: ImageFilter.sharpen,
        processedJpeg: [7],
      );

      final after = repo.byId(doc.id)!.pages.first;
      expect(after.id, before.id);
      expect(after.processedPath, isNot(before.processedPath));
      expect(await File(after.processedPath).readAsBytes(), [7]);
      expect(File(before.processedPath).existsSync(), isFalse);
      expect(after.originalPath, before.originalPath);
      expect(await File(after.originalPath).readAsBytes(), [1]);
      expect(after.corners, Quad.inset(0.2));
      expect(after.filter, ImageFilter.sharpen);
      expect(
        (await store.documents()).single.pages.first.processedPath,
        after.processedPath,
      );
    },
  );

  test(
    'si l\'enregistrement échoue, la page garde son rendu précédent',
    () async {
      final doc = await repo.create([
        capture([1], processed: [9]),
      ]);
      final before = doc.pages.first;
      await store.close();

      await expectLater(
        repo.adjustPage(
          doc.id,
          before.id,
          corners: Quad.inset(0.2),
          filter: ImageFilter.sharpen,
          processedJpeg: [7],
        ),
        throwsA(anything),
      );

      expect(await File(before.processedPath).readAsBytes(), [9]);
      store = await LocalStore.open(
        inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );
    },
  );

  test('renomme un document', () async {
    final doc = await repo.create([
      capture([1]),
    ]);

    await repo.rename(doc.id, 'Contrat de bail');

    expect(repo.byId(doc.id)!.title, 'Contrat de bail');
  });

  test(
    'un document supprimé disparaît de la liste mais reste en base',
    () async {
      final doc = await repo.create([
        capture([1]),
      ]);

      await repo.delete(doc.id);

      expect(repo.documents, isEmpty);
      expect((await store.documents()).single.deleted, isTrue);
    },
  );

  test('les documents survivent à un redémarrage', () async {
    final doc = await repo.create([
      capture([1]),
    ]);

    final again = documents();
    await again.load();

    expect(again.byId(doc.id)!.pages, hasLength(1));
    again.dispose();
  });

  test('sans compte, rien ne part vers le serveur', () async {
    final doc = await repo.create([
      capture([1]),
    ]);

    await repo.rename(doc.id, 'Bail');

    expect(server.requests, isEmpty);
    expect(repo.byId(doc.id)!.syncState, SyncState.pendingUpload);
    expect(repo.withServer, isFalse);
  });

  group('connecté', () {
    Future<void> connect() async {
      server.accounts['alice@example.com'] = 'correct horse battery';
      await account.login('alice@example.com', 'correct horse battery');
    }

    test('un document créé part aussitôt vers le compte', () async {
      await connect();

      final doc = await repo.create([
        capture([1]),
      ]);

      expect(server.documents[doc.id]!.pages, hasLength(1));
      expect(repo.byId(doc.id)!.syncState, SyncState.synced);
      expect(repo.byId(doc.id)!.pages.single.syncState, SyncState.synced);
    });

    /// La synchro lancée par la connexion tourne en arrière-plan.
    Future<void> eventually(bool Function() done) async {
      for (var i = 0; i < 200 && !done(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }

    test(
      'à la connexion, les documents créés sans compte partent vers le compte',
      () async {
        final doc = await repo.create([
          capture([1]),
        ]);

        await connect();
        await eventually(
          () => repo.byId(doc.id)?.syncState == SyncState.synced,
        );

        expect(server.documents.keys, [doc.id]);
        expect(repo.byId(doc.id)!.syncState, SyncState.synced);
      },
    );

    test(
      'à la connexion, tous les documents du compte sont récupérés',
      () async {
        await store.setLastDocumentSync(DateTime.utc(2030));
        server.documentFromAnotherDevice('d9', ['a']);

        await connect();
        await eventually(() => repo.byId('d9') != null);

        expect(repo.documents.map((d) => d.id), ['d9']);
      },
    );

    test(
      'une erreur inattendue de synchro ne fait pas échouer l\'action locale',
      () async {
        await connect();
        server.documentChangesBody = '[{"id": 1}]';

        final doc = await repo.create([
          capture([1]),
        ]);

        expect(repo.byId(doc.id), isNotNull);
        expect(repo.lastReport!.errors, isNotEmpty);
      },
    );

    test(
      'les documents d\'un autre appareil sont reçus à la synchronisation',
      () async {
        await connect();
        await repo.sync();
        server.documentFromAnotherDevice('d9', ['a']);

        await repo.sync();

        expect(repo.documents.map((d) => d.id), ['d9']);
      },
    );

    test('faute d\'espace en ligne, le document reste sur l\'appareil avec un rapport', () async {
      await connect();
      server.quotaFull = true;

      final doc = await repo.create([
        capture([1]),
      ]);

      expect(repo.documents.map((d) => d.id), [doc.id]);
      expect(repo.byId(doc.id)!.syncState, SyncState.pendingUpload);
      expect(repo.lastReport!.refusedForQuota, 1);
    });

    test('une session refusée déconnecte sans rien perdre', () async {
      await connect();
      server.expireSessions();

      final doc = await repo.create([
        capture([1]),
      ]);

      expect(account.signedIn, isFalse);
      expect(repo.byId(doc.id)!.syncState, SyncState.pendingUpload);
    });
  });
}

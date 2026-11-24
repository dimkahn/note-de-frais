import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_de_frais/account/data/account_repository.dart';
import 'package:note_de_frais/expense/data/expense_repository.dart';
import 'package:note_de_frais/shared/data/file_store.dart';
import 'package:note_de_frais/shared/data/local_store.dart';
import 'package:note_de_frais/account/domain/account.dart';
import 'package:note_de_frais/expense/domain/expense.dart';
import 'package:note_de_frais/scan/domain/quad.dart';
import 'package:note_de_frais/scan/domain/rotation.dart';
import 'package:note_de_frais/scan/domain/receipt_text_reader.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/fake_server.dart';
import '../../support/fake_biometric_auth.dart';
import '../../support/memory_device_key_store.dart';
import '../../support/memory_session_store.dart';

void main() {
  sqfliteFfiInit();
  late Directory dir;
  late LocalStore store;
  late FakeServer server;
  late MemorySessionStore sessions;
  late AccountRepository account;
  late ExpenseRepository repo;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ndf_repo');
    store = await LocalStore.open(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    server = FakeServer();
    // Connecté par défaut : session « jeton » reconnue par le faux serveur.
    sessions = MemorySessionStore(
      const Session(
        token: 'jeton',
        account: Account(email: 'alice@example.com', plan: Plan.free),
      ),
    );
    account = AccountRepository(
      store: store,
      sessions: sessions,
      deviceKeys: MemoryDeviceKeyStore(),
      biometrics: FakeBiometricAuth(available: false),
      httpClient: server.client,
    );
    await account.load();
    await account.saveServerAddress('http://serveur');
    repo = ExpenseRepository(
      store: store,
      files: FileStore(dir),
      httpClient: server.client,
      account: account,
      pollInterval: null,
    );
    await repo.load();
  });

  tearDown(() async {
    repo.dispose();
    account.dispose();
    await store.close();
    await dir.delete(recursive: true);
  });

  String photo() =>
      (File('${dir.path}/photo.jpg')..writeAsBytesSync([1, 2, 3])).path;

  Future<Expense> scan(ImageFilter filter) =>
      repo.captureScan(photo(), Quad.inset(0.1), filter, processedJpeg: [5]);

  test('une capture est visible immédiatement, même hors-ligne', () async {
    server.offline = true;

    final e = await scan(ImageFilter.sharpen);

    expect(repo.expenses.map((x) => x.id), [e.id]);
    expect(await File(e.originalPath!).readAsBytes(), [1, 2, 3]);
    expect(repo.lastReport?.offline, isTrue);
  });

  test('une capture est envoyée au serveur', () async {
    final e = await scan(ImageFilter.enhance);

    expect(server.expenses.keys, contains(e.id));
    expect(repo.byId(e.id)!.syncState, SyncState.synced);
  });

  test('modifier une dépense marque la correction et la synchronise', () async {
    final e = await scan(ImageFilter.enhance);

    await repo.edit(
      e.copyWith(merchant: 'Ibis', category: ExpenseCategory.hotel),
    );

    final saved = repo.byId(e.id)!;
    expect(saved.merchant, 'Ibis');
    expect(saved.userEdited, isTrue);
    expect(server.expenses[e.id]!['merchant'], 'Ibis');
  });

  test('changer de filtre relance le traitement côté serveur', () async {
    final e = await scan(ImageFilter.enhance);

    await repo.reprocess(e.id, ImageFilter.scanBw);

    expect(
      server.requests.any(
        (r) =>
            r.url.path.endsWith('/reprocess') &&
            r.url.query.contains('SCAN_BW'),
      ),
      isTrue,
    );
  });

  test('une dépense supprimée disparaît de la liste', () async {
    final e = await scan(ImageFilter.enhance);

    await repo.delete(e.id);

    expect(repo.expenses, isEmpty);
    expect(server.expenses.containsKey(e.id), isFalse);
  });

  test('un scan conserve la photo brute, affiche tout de suite l\'image recadrée et envoie le contour', () async {
    server.offline = true;
    final quad = Quad.inset(0.15);

    final e = await repo.captureScan(
      photo(),
      quad,
      ImageFilter.scanBw,
      processedJpeg: [9, 9],
    );

    final saved = repo.byId(e.id)!;
    expect(await File(saved.originalPath!).readAsBytes(), [1, 2, 3]);
    expect(await File(saved.processedPath!).readAsBytes(), [9, 9]);
    expect(saved.cropped, isTrue);
    expect(saved.corners, quad);

    server.offline = false;
    await repo.sync();
    expect(server.uploadedField('corners'), quad.format());
  });

  test('un scan pivoté garde sa rotation', () async {
    final e = await repo.captureScan(
      photo(),
      Quad.inset(0.1),
      ImageFilter.enhance,
      processedJpeg: [1],
      rotation: Rotation.clockwise90,
    );

    expect(repo.byId(e.id)!.rotation, Rotation.clockwise90);
  });

  test('pivoter une dépense relance son traitement avec la rotation', () async {
    final e = await repo.captureScan(
      photo(),
      Quad.inset(0.1),
      ImageFilter.enhance,
      processedJpeg: [1],
    );

    await repo.reprocess(
      e.id,
      ImageFilter.enhance,
      rotation: Rotation.clockwise180,
      processedJpeg: [2],
    );

    expect(repo.byId(e.id)!.rotation, Rotation.clockwise180);
    final reprocess = server.requests.lastWhere(
      (r) => r.url.path.endsWith('/reprocess'),
    );
    expect(reprocess.url.queryParameters['rotation'], '180');
  });

  test(
    'réajuster le contour relance le traitement avec les nouveaux coins',
    () async {
      final e = await repo.captureScan(
        photo(),
        Quad.inset(0.1),
        ImageFilter.enhance,
        processedJpeg: [1],
      );

      await repo.reprocess(
        e.id,
        ImageFilter.enhance,
        corners: Quad.inset(0.2),
        processedJpeg: [2],
      );

      expect(await File(repo.byId(e.id)!.processedPath!).readAsBytes(), [2]);
      final reprocess = server.requests.lastWhere(
        (r) => r.url.path.endsWith('/reprocess'),
      );
      expect(
        reprocess.url.queryParameters['corners'],
        Quad.inset(0.2).format(),
      );
    },
  );

  group('compte', () {
    const password = 'mot de passe long';

    test(
      'sans compte, une capture reste sur l\'appareil et rien n\'est envoyé',
      () async {
        await account.logout();
        server.requests.clear();

        final e = await scan(ImageFilter.enhance);

        expect(server.requests, isEmpty);
        expect(repo.byId(e.id)!.syncState, SyncState.pendingUpload);
        expect(repo.withServer, isFalse);
      },
    );

    test('à la connexion, les dépenses locales sont envoyées vers le compte avec leur identifiant', () async {
      await account.logout();
      final e = await scan(ImageFilter.enhance);

      await account.register('alice@example.com', password);
      await repo.sync(); // attend la synchro lancée par la connexion

      expect(server.expenses.keys, [e.id]);
      final upload = server.requests.lastWhere(
        (r) => r.method == 'POST' && r.url.path == '/api/expenses',
      );
      expect(
        upload.headers['Authorization'],
        'Bearer ${account.session!.token}',
      );
      expect(repo.byId(e.id)!.syncState, SyncState.synced);
    });

    test('se reconnecter ne renvoie pas les dépenses déjà envoyées', () async {
      await account.logout();
      await scan(ImageFilter.enhance);
      await account.register('alice@example.com', password);
      await repo.sync();
      await account.logout();
      server.requests.clear();

      await account.login('alice@example.com', password);
      await repo.sync();

      expect(
        server.requests.where(
          (r) => r.method == 'POST' && r.url.path == '/api/expenses',
        ),
        isEmpty,
      );
    });

    test(
      'à la connexion, toutes les dépenses du compte sont récupérées',
      () async {
        server.processed('recente');
        await repo.sync(); // dernière synchro mémorisée
        await account.logout();
        server.processed('ancienne');
        server.expenses['ancienne']!['updatedAt'] = '2020-01-01T00:00:00Z';

        await account.register('bob@example.com', password);
        await repo.sync();

        expect(repo.byId('ancienne'), isNotNull);
      },
    );

    test(
      'une session refusée déconnecte en conservant les dépenses locales',
      () async {
        final e = await scan(ImageFilter.enhance);
        server.expireSessions();

        await repo.edit(e.copyWith(merchant: 'Ibis'));

        expect(account.signedIn, isFalse);
        expect(repo.byId(e.id)!.merchant, 'Ibis');
        expect(repo.byId(e.id)!.syncState, SyncState.pendingUpdate);
      },
    );
  });

  group('offre et espace en ligne', () {
    test(
      'après un envoi, l\'usage du compte est relu sur le serveur',
      () async {
        server.usedBytes = 1234;

        await scan(ImageFilter.enhance);
        await pumpEventQueue();

        expect(account.session!.account.usage?.usedBytes, 1234);
      },
    );

    test(
      'après un refus faute d\'espace, l\'usage du compte est relu',
      () async {
        server.quotaFull = true;
        server.usedBytes = server.quotaBytes;

        await scan(ImageFilter.enhance);

        expect(account.session!.account.usage?.fraction, 1);
      },
    );

    test(
      'une capture refusée faute d\'espace n\'est pas renvoyée en boucle',
      () async {
        final polling = ExpenseRepository(
          store: store,
          files: FileStore(dir),
          httpClient: server.client,
          account: account,
          pollInterval: const Duration(milliseconds: 5),
        );
        await polling.load();
        server.quotaFull = true;

        await polling.captureScan(
          photo(),
          Quad.inset(0.1),
          ImageFilter.enhance,
          processedJpeg: [5],
        );
        await Future<void>.delayed(const Duration(milliseconds: 60));

        final uploads = server.requests.where(
          (r) => r.method == 'POST' && r.url.path == '/api/expenses',
        );
        expect(uploads, hasLength(1));
        expect(polling.lastReport!.refusedForQuota, 1);
        polling.dispose();
      },
    );
  });

  group('lecture du justificatif sur l\'appareil', () {
    const ticket = 'CARREFOUR MARKET\n14/03/2026\nTOTAL TTC 5,70 €';

    ExpenseRepository withReader(ReceiptTextReader reader) => ExpenseRepository(
      store: store,
      files: FileStore(dir),
      httpClient: server.client,
      account: account,
      pollInterval: null,
      textReader: reader,
    );

    test('pré-remplit une capture à partir de l\'image recadrée', () async {
      final reader = _FakeTextReader(ticket);
      final local = withReader(reader);
      await local.load();

      final e = await local.captureScan(
        photo(),
        Quad.inset(0.1),
        ImageFilter.enhance,
        processedJpeg: [5],
      );

      final saved = local.byId(e.id)!;
      expect(reader.paths, [saved.processedPath]);
      expect(saved.merchant, 'CARREFOUR MARKET');
      expect(saved.amountTotal, '5.70');
      expect(saved.expenseDate, DateTime(2026, 3, 14));
      expect(saved.prefilled, isTrue);
      local.dispose();
    });

    test('une lecture en échec n\'empêche pas l\'enregistrement', () async {
      final local = withReader(
        _FakeTextReader(null, error: StateError('ML Kit')),
      );
      await local.load();

      final e = await local.captureScan(
        photo(),
        Quad.inset(0.1),
        ImageFilter.enhance,
        processedJpeg: [5],
      );

      expect(local.byId(e.id), isNotNull);
      expect(local.byId(e.id)!.amountTotal, isNull);
      local.dispose();
    });

    test('avec serveur, le pré-remplissage reste affiché sans être envoyé comme correction', () async {
      final local = withReader(_FakeTextReader(ticket));
      await local.load();

      final e = await local.captureScan(
        photo(),
        Quad.inset(0.1),
        ImageFilter.enhance,
        processedJpeg: [5],
      );

      expect(server.expenses.keys, contains(e.id));
      expect(server.requests.where((r) => r.method == 'PUT'), isEmpty);
      expect(local.byId(e.id)!.amountTotal, '5.70');
      local.dispose();
    });
  });
}

final class _FakeTextReader implements ReceiptTextReader {
  _FakeTextReader(this.text, {this.error});

  final String? text;
  final Object? error;
  final paths = <String>[];

  @override
  Future<String?> read(String imagePath) async {
    paths.add(imagePath);
    if (error != null) throw error!;
    return text;
  }
}

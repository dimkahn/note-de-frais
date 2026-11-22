import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_de_frais/data/expense_api.dart';
import 'package:note_de_frais/data/file_store.dart';
import 'package:note_de_frais/data/local_store.dart';
import 'package:note_de_frais/data/sync_service.dart';
import 'package:note_de_frais/domain/expense.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/fake_server.dart';

void main() {
  sqfliteFfiInit();
  late Directory dir;
  late LocalStore store;
  late FileStore files;
  late FakeServer server;
  late SyncService sync;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ndf_sync');
    store = await LocalStore.open(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    files = FileStore(dir);
    server = FakeServer();
    final api = ExpenseApi(
      client: server.client,
      settings: () =>
          const ServerSettings(baseUrl: 'http://serveur', token: 'secret'),
    );
    sync = SyncService(store: store, api: api, files: files);
  });

  tearDown(() async {
    await store.close();
    await dir.delete(recursive: true);
  });

  Future<Expense> captured(String id) async {
    final source = File('${dir.path}/$id.jpg')..writeAsBytesSync([1, 2, 3]);
    final original = await files.saveOriginal(id, source.path);
    final e = Expense.draft(
      id: id,
      originalPath: original.path,
      filter: ImageFilter.scanBw,
    );
    await store.save(e);
    return e;
  }

  test('envoie les nouvelles captures avec leur identifiant, leur filtre et le jeton', () async {
    await captured('a');

    await sync.sync();

    final upload = server.requests.firstWhere((r) => r.method == 'POST');
    final body = utf8.decode(upload.bodyBytes, allowMalformed: true);
    expect(body, contains('name="id"\r\n\r\na'));
    expect(body, contains('SCAN_BW'));
    expect(upload.headers['X-Api-Token'], 'secret');
    expect((await store.get('a'))!.syncState, SyncState.synced);
  });

  test('récupère les informations extraites et l\'image traitée', () async {
    await captured('a');
    await sync.sync();
    server.processed('a');

    await sync.sync();

    final e = (await store.get('a'))!;
    expect(e.merchant, 'Le Bistrot');
    expect(e.amountTotal, '42.50');
    expect(await File(e.processedPath!).readAsBytes(), [7, 7]);
    expect(await File(e.originalPath!).readAsBytes(), [
      1,
      2,
      3,
    ], reason: 'original local intact');
  });

  test('hors-ligne, la capture reste en attente et sera renvoyée', () async {
    await captured('a');
    server.offline = true;

    final report = await sync.sync();

    expect(report.offline, isTrue);
    expect((await store.get('a'))!.syncState, SyncState.pendingUpload);

    server.offline = false;
    await sync.sync();
    expect((await store.get('a'))!.syncState, SyncState.synced);
  });

  test('pousse les corrections manuelles', () async {
    await captured('a');
    await sync.sync();
    final e = (await store.get('a'))!;
    await store.save(
      e.withEditedFields(e.copyWith(merchant: 'Corrigé', amountTotal: '10.00')),
    );

    await sync.sync();

    final put = server.requests.lastWhere((r) => r.method == 'PUT');
    expect(jsonDecode(put.body)['merchant'], 'Corrigé');
    expect((await store.get('a'))!.syncState, SyncState.synced);
  });

  test(
    'une modification locale non envoyée n\'est pas écrasée par le serveur',
    () async {
      await captured('a');
      await sync.sync();
      final e = (await store.get('a'))!;
      await store.save(e.withEditedFields(e.copyWith(merchant: 'Local')));
      server.offline = true;
      await sync.sync();
      server.offline = false;
      server.processed('a', merchant: 'Serveur');

      await sync.sync();

      expect((await store.get('a'))!.merchant, 'Local');
    },
  );

  test(
    'importe les dépenses créées sur un autre appareil, original compris',
    () async {
      server.processed('autre');

      await sync.sync();

      final e = (await store.get('autre'))!;
      expect(e.merchant, 'Le Bistrot');
      expect(await File(e.originalPath!).readAsBytes(), [1, 1]);
    },
  );

  test('propage les suppressions', () async {
    await captured('a');
    await sync.sync();
    await store.save(
      (await store.get('a'))!
          .copyWith(deleted: true, syncState: SyncState.pendingDelete),
    );

    await sync.sync();

    expect(server.requests.any((r) => r.method == 'DELETE'), isTrue);
    expect((await store.get('a'))!.syncState, SyncState.synced);
  });
}

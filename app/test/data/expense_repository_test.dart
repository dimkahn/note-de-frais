import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_de_frais/data/expense_api.dart';
import 'package:note_de_frais/data/expense_repository.dart';
import 'package:note_de_frais/data/file_store.dart';
import 'package:note_de_frais/data/local_store.dart';
import 'package:note_de_frais/domain/expense.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/fake_server.dart';

void main() {
  sqfliteFfiInit();
  late Directory dir;
  late LocalStore store;
  late FakeServer server;
  late ExpenseRepository repo;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ndf_repo');
    store = await LocalStore.open(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    server = FakeServer();
    repo = ExpenseRepository(
      store: store,
      files: FileStore(dir),
      httpClient: server.client,
      pollInterval: null,
    );
    await repo.load();
    await repo.saveSettings(const ServerSettings(baseUrl: 'http://serveur'));
  });

  tearDown(() async {
    repo.dispose();
    await store.close();
    await dir.delete(recursive: true);
  });

  String photo() =>
      (File('${dir.path}/photo.jpg')..writeAsBytesSync([1, 2, 3])).path;

  test('une capture est visible immédiatement, même hors-ligne', () async {
    server.offline = true;

    final e = await repo.capture(photo(), ImageFilter.sharpen);

    expect(repo.expenses.map((x) => x.id), [e.id]);
    expect(await File(e.originalPath!).readAsBytes(), [1, 2, 3]);
    expect(repo.lastReport?.offline, isTrue);
  });

  test('une capture est envoyée au serveur', () async {
    final e = await repo.capture(photo(), ImageFilter.enhance);

    expect(server.expenses.keys, contains(e.id));
    expect(repo.byId(e.id)!.syncState, SyncState.synced);
  });

  test('modifier une dépense marque la correction et la synchronise', () async {
    final e = await repo.capture(photo(), ImageFilter.enhance);

    await repo.edit(
      e.copyWith(merchant: 'Ibis', category: ExpenseCategory.hotel),
    );

    final saved = repo.byId(e.id)!;
    expect(saved.merchant, 'Ibis');
    expect(saved.userEdited, isTrue);
    expect(server.expenses[e.id]!['merchant'], 'Ibis');
  });

  test('changer de filtre relance le traitement côté serveur', () async {
    final e = await repo.capture(photo(), ImageFilter.enhance);

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
    final e = await repo.capture(photo(), ImageFilter.enhance);

    await repo.delete(e.id);

    expect(repo.expenses, isEmpty);
    expect(server.expenses.containsKey(e.id), isFalse);
  });

  test('les réglages serveur sont conservés', () async {
    final reopened = ExpenseRepository(
      store: store,
      files: FileStore(dir),
      httpClient: server.client,
      pollInterval: null,
    );

    await reopened.load();

    expect(reopened.settings.baseUrl, 'http://serveur');
    reopened.dispose();
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:note_de_frais/data/local_store.dart';

import 'dart:io';

import 'package:note_de_frais/domain/expense.dart';
import 'package:note_de_frais/domain/quad.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late LocalStore store;

  setUp(() async {
    store = await LocalStore.open(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
  });

  tearDown(() => store.close());

  test('enregistre puis relit une dépense', () async {
    final e = Expense.draft(
      id: 'a',
      originalPath: '/o.jpg',
      filter: ImageFilter.enhance,
    );

    await store.save(e);

    expect(await store.get('a'), e);
  });

  test('save remplace la version précédente', () async {
    final e = Expense.draft(
      id: 'a',
      originalPath: '/o.jpg',
      filter: ImageFilter.enhance,
    );
    await store.save(e);

    await store.save(e.copyWith(merchant: 'Ibis'));

    expect((await store.all()).single.merchant, 'Ibis');
  });

  test('liste les dépenses à synchroniser', () async {
    await store.save(
      Expense.draft(id: 'a', originalPath: '/o', filter: ImageFilter.none),
    );
    await store.save(const Expense(id: 'b'));

    final pending = await store.pendingSync();

    expect(pending.map((e) => e.id), ['a']);
  });

  test('mémorise la date de dernière synchronisation', () async {
    expect(await store.lastSync(), isNull);

    await store.setLastSync(DateTime.utc(2026, 3, 10, 12));

    expect(await store.lastSync(), DateTime.utc(2026, 3, 10, 12));
  });

  test('mémorise les réglages', () async {
    await store.setSetting('baseUrl', 'http://serveur');

    expect(await store.setting('baseUrl'), 'http://serveur');
    expect(await store.setting('inconnu'), isNull);
  });

  test('conserve le contour choisi', () async {
    final e = Expense.draft(
      id: 'a',
      originalPath: '/o',
      filter: ImageFilter.none,
    ).copyWith(corners: Quad.inset(0.2));

    await store.save(e);

    expect((await store.get('a'))!.corners, Quad.inset(0.2));
  });

  test('migre une base de la version 1 sans perte', () async {
    final dir = await Directory.systemTemp.createTemp('ndf_migration');
    final path = '${dir.path}/v1.db';
    final v1 = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE expense (id TEXT PRIMARY KEY, merchant TEXT, category TEXT, expense_date TEXT, '
            'amount_total TEXT, amount_vat TEXT, currency TEXT, city TEXT, country TEXT, address TEXT, '
            'payment_method TEXT, description TEXT, user_edited INTEGER NOT NULL DEFAULT 0, filter TEXT NOT NULL, '
            'cropped INTEGER NOT NULL DEFAULT 0, has_processed_image INTEGER NOT NULL DEFAULT 0, '
            'status TEXT NOT NULL, processing_error TEXT, deleted INTEGER NOT NULL DEFAULT 0, created_at TEXT, '
            'server_updated_at TEXT, sync_state TEXT NOT NULL, original_path TEXT, processed_path TEXT)',
          );
          await db.execute(
            'CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT)',
          );
          await db.insert('expense', {
            'id': 'ancien',
            'merchant': 'Ibis',
            'filter': 'ENHANCE',
            'status': 'DONE',
            'sync_state': 'synced',
          });
        },
      ),
    );
    await v1.close();

    final migrated = await LocalStore.open(path, factory: databaseFactoryFfi);
    await migrated.save(
      (await migrated.get('ancien'))!
          .copyWith(corners: Quad.inset(0.1), prefilled: true),
    );

    expect((await migrated.get('ancien'))!.merchant, 'Ibis');
    expect((await migrated.get('ancien'))!.corners, Quad.inset(0.1));
    expect((await migrated.get('ancien'))!.prefilled, isTrue);
    await migrated.close();
    await dir.delete(recursive: true);
  });
}

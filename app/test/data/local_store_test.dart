import 'package:flutter_test/flutter_test.dart';
import 'package:note_de_frais/data/local_store.dart';
import 'package:note_de_frais/domain/expense.dart';
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
}

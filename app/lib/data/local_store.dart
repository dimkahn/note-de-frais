import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../domain/expense.dart';

/// Base SQLite locale : source de vérité de l'application (hors-ligne d'abord).
final class LocalStore {
  LocalStore._(this._db);

  final Database _db;

  static const _schemaVersion = 3;

  static Future<LocalStore> open(
    String path, {
    required DatabaseFactory factory,
  }) async {
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: _schemaVersion,
        onCreate: _create,
        onUpgrade: _upgrade,
      ),
    );
    return LocalStore._(db);
  }

  static Future<void> _create(Database db, int version) async {
    await db.execute('''
      CREATE TABLE expense (
        id TEXT PRIMARY KEY,
        merchant TEXT, category TEXT, expense_date TEXT,
        amount_total TEXT, amount_vat TEXT, currency TEXT,
        city TEXT, country TEXT, address TEXT, payment_method TEXT, description TEXT,
        user_edited INTEGER NOT NULL DEFAULT 0,
        prefilled INTEGER NOT NULL DEFAULT 0,
        filter TEXT NOT NULL,
        cropped INTEGER NOT NULL DEFAULT 0,
        corners TEXT,
        has_processed_image INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL,
        processing_error TEXT,
        deleted INTEGER NOT NULL DEFAULT 0,
        created_at TEXT, server_updated_at TEXT,
        sync_state TEXT NOT NULL,
        original_path TEXT, processed_path TEXT
      )''');
    await db.execute('CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT)');
  }

  /// Migrations successives : chaque version ajoute ce qui lui manque, sans perte de données.
  static Future<void> _upgrade(Database db, int from, int to) async {
    if (from < 2) {
      await db.execute('ALTER TABLE expense ADD COLUMN corners TEXT');
    }
    if (from < 3) {
      await db.execute(
        'ALTER TABLE expense ADD COLUMN prefilled INTEGER NOT NULL DEFAULT 0',
      );
    }
  }

  Future<void> save(Expense e) => _db.insert(
    'expense',
    e.toDb(),
    conflictAlgorithm: ConflictAlgorithm.replace,
  );

  Future<Expense?> get(String id) async {
    final rows = await _db.query('expense', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Expense.fromDb(rows.single);
  }

  Future<List<Expense>> all() async =>
      (await _db.query('expense')).map(Expense.fromDb).toList();

  Future<List<Expense>> pendingSync() async => (await _db.query(
    'expense',
    where: 'sync_state != ?',
    whereArgs: [SyncState.synced.name],
    orderBy: 'created_at',
  )).map(Expense.fromDb).toList();

  Future<DateTime?> lastSync() async {
    final rows = await _db.query(
      'meta',
      where: 'key = ?',
      whereArgs: ['last_sync'],
    );
    return rows.isEmpty
        ? null
        : DateTime.parse(rows.single['value']! as String);
  }

  Future<void> setLastSync(DateTime at) => _db.insert('meta', {
    'key': 'last_sync',
    'value': at.toUtc().toIso8601String(),
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<String?> setting(String key) async {
    final rows = await _db.query(
      'meta',
      where: 'key = ?',
      whereArgs: ['setting.$key'],
    );
    return rows.isEmpty ? null : rows.single['value'] as String?;
  }

  Future<void> setSetting(String key, String value) => _db.insert('meta', {
    'key': 'setting.$key',
    'value': value,
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> close() => _db.close();
}

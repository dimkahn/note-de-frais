import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../domain/document.dart';
import '../domain/expense.dart';
import '../domain/quad.dart';

/// Base SQLite locale : source de vérité de l'application (hors-ligne d'abord).
final class LocalStore {
  LocalStore._(this._db);

  final Database _db;

  static const _schemaVersion = 4;

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
    await _createDocumentTables(db);
  }

  static Future<void> _createDocumentTables(Database db) async {
    await db.execute('''
      CREATE TABLE document (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted INTEGER NOT NULL DEFAULT 0
      )''');
    await db.execute('''
      CREATE TABLE document_page (
        id TEXT PRIMARY KEY,
        document_id TEXT NOT NULL REFERENCES document(id),
        position INTEGER NOT NULL,
        original_path TEXT NOT NULL,
        processed_path TEXT NOT NULL,
        corners TEXT NOT NULL,
        filter TEXT NOT NULL
      )''');
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
    if (from < 4) await _createDocumentTables(db);
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

  /// La prochaine synchronisation récupérera tout (changement de compte).
  Future<void> clearLastSync() =>
      _db.delete('meta', where: 'key = ?', whereArgs: ['last_sync']);

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

  // --- Documents ---

  /// Enregistre le document et remplace sa liste de pages, en une transaction.
  Future<void> saveDocument(ScannedDocument doc) => _db.transaction((tx) async {
    await tx.insert('document', {
      'id': doc.id,
      'title': doc.title,
      'created_at': doc.createdAt.toUtc().toIso8601String(),
      'updated_at': doc.updatedAt.toUtc().toIso8601String(),
      'deleted': doc.deleted ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await tx.delete(
      'document_page',
      where: 'document_id = ?',
      whereArgs: [doc.id],
    );
    for (final (i, page) in doc.pages.indexed) {
      await tx.insert('document_page', {
        'id': page.id,
        'document_id': doc.id,
        'position': i,
        'original_path': page.originalPath,
        'processed_path': page.processedPath,
        'corners': page.corners.format(),
        'filter': page.filter.code,
      });
    }
  });

  /// Tous les documents (suppressions logiques comprises), du plus récent au plus ancien.
  Future<List<ScannedDocument>> documents() async {
    final pages = <String, List<ScannedPage>>{};
    for (final row in await _db.query('document_page', orderBy: 'position')) {
      (pages[row['document_id']! as String] ??= []).add(
        ScannedPage(
          id: row['id']! as String,
          originalPath: row['original_path']! as String,
          processedPath: row['processed_path']! as String,
          corners: Quad.parse(row['corners']! as String),
          filter: ImageFilter.fromCode(row['filter'] as String?),
        ),
      );
    }
    return [
      for (final row in await _db.query('document', orderBy: 'created_at DESC'))
        ScannedDocument(
          id: row['id']! as String,
          title: row['title']! as String,
          createdAt: DateTime.parse(row['created_at']! as String),
          updatedAt: DateTime.parse(row['updated_at']! as String),
          pages: pages[row['id']] ?? const [],
          deleted: row['deleted'] == 1,
        ),
    ];
  }

  Future<void> close() => _db.close();
}

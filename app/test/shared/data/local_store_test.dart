import 'package:flutter_test/flutter_test.dart';
import 'package:note_de_frais/shared/data/local_store.dart';

import 'dart:io';

import 'package:note_de_frais/document/domain/document.dart';
import 'package:note_de_frais/expense/domain/expense.dart';
import 'package:note_de_frais/scan/domain/quad.dart';
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

  test('oublie la date de dernière synchronisation', () async {
    await store.setLastSync(DateTime.utc(2026, 3, 10, 12));

    await store.clearLastSync();

    expect(await store.lastSync(), isNull);
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
    await migrated.saveDocument(
      ScannedDocument.create(id: 'doc', createdAt: DateTime.utc(2026)),
    );
    expect(await migrated.documents(), hasLength(1));
    await migrated.close();
    await dir.delete(recursive: true);
  });

  group('documents', () {
    final at = DateTime.utc(2026, 11, 23, 9);
    ScannedPage page(String id, ImageFilter filter) => ScannedPage(
      id: id,
      originalPath: '/docs/$id/original.jpg',
      processedPath: '/docs/$id/processed.jpg',
      corners: Quad.inset(0.1),
      filter: filter,
    );

    test('enregistre un document et relit ses pages dans l\'ordre', () async {
      final doc = ScannedDocument.create(id: 'd1', createdAt: at)
          .withPage(page('p2', ImageFilter.scanBw), at: at)
          .withPage(page('p1', ImageFilter.enhance), at: at);

      await store.saveDocument(doc);

      final read = (await store.documents()).single;
      expect(read.title, doc.title);
      expect(read.createdAt, at);
      expect(read.pages.map((p) => p.id), ['p2', 'p1']);
      expect(read.pages.first.filter, ImageFilter.scanBw);
      expect(read.pages.first.corners, Quad.inset(0.1));
    });

    test('un nouvel enregistrement remplace les pages', () async {
      final doc = ScannedDocument.create(id: 'd1', createdAt: at)
          .withPage(page('p1', ImageFilter.none), at: at)
          .withPage(page('p2', ImageFilter.none), at: at);
      await store.saveDocument(doc);

      await store.saveDocument(
        doc.withoutPage('p1', at: at).renamed('Bail', at: at),
      );

      final read = (await store.documents()).single;
      expect(read.title, 'Bail');
      expect(read.pages.map((p) => p.id), ['p2']);
    });

    test('liste les documents du plus récent au plus ancien', () async {
      await store.saveDocument(
        ScannedDocument.create(id: 'vieux', createdAt: at),
      );
      await store.saveDocument(
        ScannedDocument.create(
          id: 'recent',
          createdAt: at.add(const Duration(days: 1)),
        ),
      );

      expect((await store.documents()).map((d) => d.id), ['recent', 'vieux']);
    });

    test(
      'conserve l\'état de synchronisation du document et de ses pages',
      () async {
        final doc = ScannedDocument(
          id: 'd1',
          title: 'Bail',
          createdAt: at,
          updatedAt: at,
          syncState: SyncState.pendingUpdate,
          pages: [
            ScannedPage(
              id: 'p1',
              originalPath: '/docs/p1/original.jpg',
              processedPath: '/docs/p1/processed.jpg',
              corners: Quad.inset(0.1),
              filter: ImageFilter.none,
              syncState: SyncState.pendingReprocess,
              renderVersion: 3,
            ),
          ],
        );

        await store.saveDocument(doc);

        final read = (await store.documents()).single;
        expect(read.syncState, SyncState.pendingUpdate);
        expect(read.pages.single.syncState, SyncState.pendingReprocess);
        expect(read.pages.single.renderVersion, 3);
      },
    );

    test('liste les documents à synchroniser', () async {
      await store.saveDocument(
        ScannedDocument(
          id: 'envoye',
          title: 'A',
          createdAt: at,
          updatedAt: at,
          syncState: SyncState.synced,
        ),
      );
      await store.saveDocument(
        ScannedDocument.create(id: 'local', createdAt: at),
      );

      expect((await store.pendingDocuments()).map((d) => d.id), ['local']);
      expect((await store.document('envoye'))!.title, 'A');
      expect(await store.document('inconnu'), isNull);
    });

    test(
      'ne marque envoyé qu\'un document resté tel qu\'il a été envoyé',
      () async {
        final sent = ScannedDocument.create(id: 'd1', createdAt: at);
        await store.saveDocument(sent);
        await store.markDocumentSynced('d1', updatedAt: sent.updatedAt);
        final renamed = (await store.document('d1'))!
            .renamed('Bail', at: at.add(const Duration(minutes: 1)));
        await store.saveDocument(renamed);

        await store.markDocumentSynced('d1', updatedAt: sent.updatedAt);

        expect(
          (await store.document('d1'))!.syncState,
          SyncState.pendingUpdate,
        );
      },
    );

    test(
      'ne marque envoyée qu\'une page dont le rendu n\'a pas changé',
      () async {
        final doc = ScannedDocument.create(id: 'd1', createdAt: at)
            .withPage(page('p1', ImageFilter.none), at: at)
            .withPage(page('p2', ImageFilter.none), at: at);
        await store.saveDocument(doc);

        await store.markPageSynced(
          'p1',
          processedPath: '/docs/p1/processed.jpg',
          renderVersion: 2,
        );
        await store.markPageSynced(
          'p2',
          processedPath: '/docs/p2/ancien-rendu.jpg',
          renderVersion: 2,
        );

        final pages = (await store.document('d1'))!.pages;
        expect(pages[0].syncState, SyncState.synced);
        expect(pages[0].renderVersion, 2);
        expect(pages[1].syncState, SyncState.pendingUpload);
      },
    );

    test(
      'mémorise et oublie la date de synchro des documents à part',
      () async {
        await store.setLastDocumentSync(at);

        expect(await store.lastDocumentSync(), at);
        expect(await store.lastSync(), isNull);
        await store.clearLastSync();
        expect(await store.lastDocumentSync(), at);
        await store.clearLastDocumentSync();
        expect(await store.lastDocumentSync(), isNull);
      },
    );

    test(
      'les documents d\'avant la synchro attendent leur premier envoi',
      () async {
        final dir = await Directory.systemTemp.createTemp('ndf_migration_v4');
        final path = '${dir.path}/v4.db';
        final v4 = await databaseFactoryFfi.openDatabase(
          path,
          options: OpenDatabaseOptions(
            version: 4,
            onCreate: (db, _) async {
              await db.execute(
                'CREATE TABLE expense (id TEXT PRIMARY KEY, sync_state TEXT NOT NULL)',
              );
              await db.execute(
                'CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT)',
              );
              await db.execute(
                'CREATE TABLE document (id TEXT PRIMARY KEY, title TEXT NOT NULL, created_at TEXT NOT NULL, '
                'updated_at TEXT NOT NULL, deleted INTEGER NOT NULL DEFAULT 0)',
              );
              await db.execute(
                'CREATE TABLE document_page (id TEXT PRIMARY KEY, document_id TEXT NOT NULL, '
                'position INTEGER NOT NULL, original_path TEXT NOT NULL, processed_path TEXT NOT NULL, '
                'corners TEXT NOT NULL, filter TEXT NOT NULL)',
              );
              await db.insert('document', {
                'id': 'ancien',
                'title': 'Bail',
                'created_at': at.toIso8601String(),
                'updated_at': at.toIso8601String(),
              });
              await db.insert('document_page', {
                'id': 'p1',
                'document_id': 'ancien',
                'position': 0,
                'original_path': '/docs/p1/original.jpg',
                'processed_path': '/docs/p1/processed.jpg',
                'corners': Quad.inset(0.1).format(),
                'filter': 'ENHANCE',
              });
            },
          ),
        );
        await v4.close();

        final migrated = await LocalStore.open(
          path,
          factory: databaseFactoryFfi,
        );

        final doc = (await migrated.pendingDocuments()).single;
        expect(doc.syncState, SyncState.pendingUpload);
        expect(doc.pages.single.syncState, SyncState.pendingUpload);
        await migrated.close();
        await dir.delete(recursive: true);
      },
    );
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_de_frais/data/document_repository.dart';
import 'package:note_de_frais/data/file_store.dart';
import 'package:note_de_frais/data/local_store.dart';
import 'package:note_de_frais/domain/expense.dart';
import 'package:note_de_frais/domain/quad.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Directory dir;
  late LocalStore store;
  late DocumentRepository repo;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ndf_docs');
    store = await LocalStore.open(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    repo = DocumentRepository(store: store, files: FileStore(dir));
    await repo.load();
  });

  tearDown(() async {
    repo.dispose();
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

    final again = DocumentRepository(store: store, files: FileStore(dir));
    await again.load();

    expect(again.byId(doc.id)!.pages, hasLength(1));
    again.dispose();
  });
}

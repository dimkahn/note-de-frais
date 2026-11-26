import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_de_frais/document/data/document_repository.dart';
import 'package:note_de_frais/document/domain/document.dart';
import 'package:note_de_frais/expense/domain/expense.dart';
import 'package:note_de_frais/scan/domain/page_scanner.dart';
import 'package:note_de_frais/scan/domain/quad.dart';
import 'package:note_de_frais/scan/domain/rotation.dart';
import 'package:note_de_frais/scan/ui/adjust_screen.dart';
import 'package:note_de_frais/scan/ui/capture.dart';
import 'package:note_de_frais/shared/data/file_store.dart';
import 'package:note_de_frais/shared/data/local_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/settle.dart';
import '../../support/signed_out_account.dart';
import '../data/document_scanner_test.dart' show uniform;

/// Exécution synchrone dans le test (pas d'isolate).
Future<T> _inline<T>(T Function() work) async => work();

/// Scanner système simulé : rend les pages prévues.
final class _FakeScanner implements PageScanner {
  _FakeScanner(this.pages);

  final List<String> pages;

  @override
  Future<List<String>?> scan({int? pageLimit}) async => pages;
}

void main() {
  sqfliteFfiInit();
  late Directory dir;
  late LocalStore store;
  late DocumentRepository repo;
  late ScannedDocument doc;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ndf_edit');
    store = await LocalStore.open(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    repo = DocumentRepository(
      store: store,
      files: FileStore(dir),
      httpClient: noServer,
      account: await signedOutAccount(store),
    );
    await repo.load();
    doc = await repo.create([
      for (final b in [1, 2, 3])
        PageCapture(
          photoPath: (File(
            '${dir.path}/photo-$b.jpg',
          )..writeAsBytesSync(uniform(60, 80))).path,
          corners: Quad.inset(0.1),
          filter: ImageFilter.enhance,
          processedJpeg: [b],
        ),
    ]);
  });

  tearDown(() async {
    repo.dispose();
    await store.close();
    await dir.delete(recursive: true);
  });

  /// Page telle que la revue la rend, sans changement sauf ceux demandés.
  ScanResult reviewed(
    ScannedPage page, {
    ImageFilter? filter,
    Rotation? rotation,
    int byte = 9,
  }) => ScanResult(
    photoPath: page.originalPath,
    quad: page.corners,
    filter: filter ?? page.filter,
    rotation: rotation ?? page.rotation,
    processedJpeg: Uint8List.fromList([byte]),
  );

  List<int> rendered(int index) =>
      File(repo.byId(doc.id)!.pages[index].processedPath).readAsBytesSync();

  test('une page modifiée dans la revue est réajustée', () async {
    final [p0, p1, p2] = doc.pages;

    await saveDocumentEdit(repo, doc.id, doc.pages, [
      reviewed(p0),
      reviewed(p1, filter: ImageFilter.scanBw, rotation: Rotation.clockwise90),
      reviewed(p2),
    ]);

    final page = repo.byId(doc.id)!.pages[1];
    expect(page.filter, ImageFilter.scanBw);
    expect(page.rotation, Rotation.clockwise90);
    expect(rendered(1), [9]);
  });

  test('une page inchangée garde son rendu', () async {
    final [p0, p1, p2] = doc.pages;

    await saveDocumentEdit(repo, doc.id, doc.pages, [
      reviewed(p0),
      reviewed(p1, filter: ImageFilter.scanBw),
      reviewed(p2),
    ]);

    expect(rendered(0), [1]);
    expect(rendered(2), [3]);
  });

  test('une page supprimée dans la revue est retirée du document', () async {
    final [p0, p1, p2] = doc.pages;

    await saveDocumentEdit(repo, doc.id, doc.pages, [
      reviewed(p0),
      reviewed(p2),
    ]);

    expect(repo.byId(doc.id)!.pages.map((p) => p.id), [p0.id, p2.id]);
    expect(p1.originalPath, isNot(isEmpty));
    expect(File(p1.originalPath).existsSync(), isTrue);
  });

  test('une page ajoutée dans la revue va en fin de document', () async {
    final [p0, p1, p2] = doc.pages;
    final photo = (File('${dir.path}/new.jpg')..writeAsBytesSync([7])).path;

    await saveDocumentEdit(repo, doc.id, doc.pages, [
      reviewed(p0),
      reviewed(p1),
      reviewed(p2),
      ScanResult(
        photoPath: photo,
        quad: Quad.inset(0.2),
        filter: ImageFilter.none,
        processedJpeg: Uint8List.fromList([8]),
      ),
    ]);

    final pages = repo.byId(doc.id)!.pages;
    expect(pages, hasLength(4));
    expect(pages.last.filter, ImageFilter.none);
    expect(rendered(3), [8]);
  });

  test('une page arrivée pendant la revue (synchro) est conservée', () async {
    final [p0, p1, p2] = doc.pages;
    final edited = doc.pages;
    await repo.addPages(doc.id, [
      PageCapture(
        photoPath: (File('${dir.path}/sync.jpg')..writeAsBytesSync([5])).path,
        corners: Quad.inset(0.1),
        filter: ImageFilter.enhance,
        processedJpeg: [5],
      ),
    ]);

    await saveDocumentEdit(repo, doc.id, edited, [
      reviewed(p0),
      reviewed(p1),
      reviewed(p2),
    ]);

    expect(repo.byId(doc.id)!.pages, hasLength(4));
  });

  /// Lance la modification du document depuis une page d'accueil.
  Future<void> edit(
    WidgetTester tester, {
    List<String> scanned = const [],
  }) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => editDocument(
              context,
              repo,
              doc.id,
              pageScanner: _FakeScanner(scanned),
              compute: _inline,
            ),
            child: const Text('modifier'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('modifier'));
    await settleRealAsync(tester);
  }

  /// Laisse passer le vrai temps (base SQLite, fichiers) jusqu'à ce que [done] soit vrai.
  Future<void> until(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 100 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
  }

  testWidgets('« Ajouter » scanne de nouvelles pages, ajoutées au document', (
    tester,
  ) async {
    final photo = (File(
      '${dir.path}/new.jpg',
    )..writeAsBytesSync(uniform(60, 80))).path;
    await edit(tester, scanned: [photo]);

    await tester.tap(find.text('Ajouter'));
    await settleRealAsync(tester);
    await tester.pumpAndSettle();
    expect(find.text('Page 4 / 4'), findsOneWidget);
    await tester.tap(find.textContaining('Enregistrer'));
    await until(tester, () => repo.byId(doc.id)!.pages.length == 4);

    expect(repo.byId(doc.id)!.pages, hasLength(4));
  });

  testWidgets(
    'supprimer toutes les pages les retire du document, après confirmation',
    (tester) async {
      await edit(tester);

      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('Supprimer'));
        await settleRealAsync(tester);
      }
      expect(find.text('Retirer les 3 pages ?'), findsOneWidget);
      await tester.tap(find.text('Retirer'));
      await until(tester, () => repo.byId(doc.id)!.pages.isEmpty);

      expect(repo.byId(doc.id)!.pages, isEmpty);
    },
  );

  testWidgets('revenir en arrière ne modifie pas le document', (tester) async {
    final before = repo.byId(doc.id)!.pages;
    await edit(tester);

    await tester.tap(find.text('Pivoter'));
    await settleRealAsync(tester);
    await tester.pageBack();
    await settleRealAsync(tester);
    await until(tester, () => false);

    final after = repo.byId(doc.id)!.pages;
    expect(after.map((p) => (p.id, p.rotation, p.processedPath)), [
      for (final p in before) (p.id, p.rotation, p.processedPath),
    ]);
  });

  testWidgets(
    'annuler le retrait de toutes les pages rouvre la revue, sans rien retirer',
    (tester) async {
      await edit(tester);

      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('Supprimer'));
        await settleRealAsync(tester);
      }
      await tester.tap(find.text('Annuler'));
      await settleRealAsync(tester);
      await settleRealAsync(tester);

      expect(find.text('Page 1 / 3'), findsOneWidget);
      expect(repo.byId(doc.id)!.pages, hasLength(3));
    },
  );
}

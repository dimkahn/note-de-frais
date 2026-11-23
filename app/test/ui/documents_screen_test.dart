import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:note_de_frais/data/document_repository.dart';
import 'package:note_de_frais/data/export_service.dart';
import 'package:note_de_frais/data/file_store.dart';
import 'package:note_de_frais/data/local_store.dart';
import 'package:note_de_frais/domain/expense.dart';
import 'package:note_de_frais/domain/quad.dart';
import 'package:note_de_frais/ui/documents_screen.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:provider/provider.dart';

import '../support/temp_downloads.dart';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final class _FakeSharer implements FileSharer {
  final shared = <File>[];
  bool fail = false;

  @override
  Future<void> share(List<File> files, {required String subject}) async {
    if (fail) throw const FileSystemException('Espace disque insuffisant');
    shared.addAll(files);
  }
}

List<int> _jpeg() {
  final img = cv.Mat.fromScalar(
    80,
    60,
    cv.MatType.CV_8UC3,
    cv.Scalar(230, 230, 230),
  );
  final (_, bytes) = cv.imencode('.jpg', img);
  img.dispose();
  return bytes;
}

void main() {
  sqfliteFfiInit();
  late Directory dir;
  late LocalStore store;
  late DocumentRepository repo;
  late _FakeSharer sharer;

  Future<void> pump(
    WidgetTester tester, {
    int documents = 0,
    int pages = 2,
  }) async {
    await tester.runAsync(() async {
      await initializeDateFormatting('fr_FR');
      dir = await Directory.systemTemp.createTemp('ndf_docs_ui');
      store = await LocalStore.open(
        inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );
      repo = DocumentRepository(store: store, files: FileStore(dir));
      await repo.load();
      for (var d = 0; d < documents; d++) {
        final doc = await repo.create([
          for (var p = 0; p < pages; p++)
            PageCapture(
              photoPath: (File(
                '${dir.path}/p$d$p.jpg',
              )..writeAsBytesSync([1])).path,
              corners: Quad.inset(0.1),
              filter: ImageFilter.enhance,
              processedJpeg: _jpeg(),
            ),
        ]);
        await repo.rename(doc.id, 'Contrat $d');
      }
    });
    sharer = _FakeSharer();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: repo),
          Provider.value(
            value: ExportService(
              sharer: sharer,
              tempDir: dir,
              downloads: TempDownloads(Directory('${dir.path}/Download')),
            ),
          ),
        ],
        child: const MaterialApp(home: DocumentsScreen()),
      ),
    );
    await tester.pump();
  }

  tearDown(() async {
    repo.dispose();
    await store.close();
    await dir.delete(recursive: true);
  });

  testWidgets('sans document, invite à en scanner un', (tester) async {
    await pump(tester);

    expect(find.text('Aucun document'), findsOneWidget);
    expect(find.text('Nouveau document'), findsOneWidget);
  });

  testWidgets('liste les documents avec leur nombre de pages', (tester) async {
    await pump(tester, documents: 1, pages: 3);

    expect(find.text('Contrat 0'), findsOneWidget);
    expect(find.textContaining('3 pages'), findsOneWidget);
  });

  testWidgets('la fiche d\'un document montre ses pages numérotées', (
    tester,
  ) async {
    await pump(tester, documents: 1, pages: 2);

    await tester.tap(find.text('Contrat 0'));
    await tester.pumpAndSettle();

    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Ajouter des pages'), findsOneWidget);
  });

  testWidgets('supprime une page après confirmation', (tester) async {
    await pump(tester, documents: 1, pages: 2);
    await tester.tap(find.text('Contrat 0'));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retirer la page'));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    expect(repo.documents.single.pages, hasLength(1));
  });

  testWidgets('exporte le document en PDF', (tester) async {
    await pump(tester, documents: 1, pages: 2);
    await tester.tap(find.text('Contrat 0'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Exporter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Partager le PDF'));
    for (var i = 0; i < 40 && sharer.shared.isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }

    expect(sharer.shared.single.uri.pathSegments.last, 'Contrat 0.pdf');
  });

  Future<void> openDocument(WidgetTester tester) async {
    await tester.tap(find.text('Contrat 0'));
    await tester.pumpAndSettle();
  }

  Future<void> settleIo(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  testWidgets(
    'signale un export impossible sans prétendre à une image illisible',
    (tester) async {
      await pump(tester, documents: 1);
      sharer.fail = true;
      await openDocument(tester);

      await tester.tap(find.byTooltip('Exporter'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Partager le PDF'));
      for (
        var i = 0;
        i < 40 && find.text('Export impossible').evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }

      expect(find.text('Export impossible'), findsOneWidget);
    },
  );

  testWidgets('renomme le document depuis le menu', (tester) async {
    await pump(tester, documents: 1);
    await openDocument(tester);

    await tester.tap(find.byTooltip('Plus d\'options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Renommer'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Bail 2026');
    await tester.tap(find.widgetWithText(FilledButton, 'Renommer'));
    await settleIo(tester);

    expect(repo.documents.single.title, 'Bail 2026');
  });

  testWidgets('supprime le document après confirmation', (tester) async {
    await pump(tester, documents: 1);
    await openDocument(tester);

    await tester.tap(find.byTooltip('Plus d\'options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supprimer le document'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Supprimer'));
    await settleIo(tester);

    expect(repo.documents, isEmpty);
    expect(find.text('Aucun document'), findsOneWidget);
  });

  testWidgets(
    'retire une page depuis la lecture plein écran, sans appui long',
    (tester) async {
      await pump(tester, documents: 1, pages: 2);
      await openDocument(tester);
      await tester.tap(find.text('1'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Retirer la page'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Retirer'));
      await settleIo(tester);

      expect(repo.documents.single.pages, hasLength(1));
    },
  );

  testWidgets('enregistre le PDF dans Téléchargements et le confirme', (
    tester,
  ) async {
    await pump(tester, documents: 1);
    await openDocument(tester);

    await tester.tap(find.byTooltip('Exporter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PDF dans Téléchargements'));
    for (
      var i = 0;
      i < 40 && find.textContaining('Enregistré dans').evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }

    expect(
      find.text('Enregistré dans Téléchargements : Contrat 0.pdf'),
      findsOneWidget,
    );
    expect(File('${dir.path}/Download/Contrat 0.pdf').existsSync(), isTrue);
    expect(sharer.shared, isEmpty);
  });
}

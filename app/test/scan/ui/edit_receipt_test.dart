import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_de_frais/expense/data/expense_repository.dart';
import 'package:note_de_frais/expense/domain/expense.dart';
import 'package:note_de_frais/scan/domain/quad.dart';
import 'package:note_de_frais/scan/ui/capture.dart';
import 'package:note_de_frais/scan/ui/review_screen.dart';
import 'package:note_de_frais/shared/data/file_store.dart';
import 'package:note_de_frais/shared/data/local_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/settle.dart';
import '../../support/signed_out_account.dart';
import '../data/document_scanner_test.dart' show uniform;

/// Exécution synchrone dans le test (pas d'isolate).
Future<T> _inline<T>(T Function() work) async => work();

void main() {
  sqfliteFfiInit();
  late Directory dir;
  late LocalStore store;
  late ExpenseRepository repo;
  late Expense expense;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ndf_edit_receipt');
    store = await LocalStore.open(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    repo = ExpenseRepository(
      store: store,
      files: FileStore(dir),
      httpClient: noServer,
      account: await signedOutAccount(store),
      pollInterval: null,
    );
    await repo.load();
    final photo = (File(
      '${dir.path}/ticket.jpg',
    )..writeAsBytesSync(uniform(60, 80))).path;
    expense = await repo.captureScan(
      photo,
      Quad.inset(0.1),
      ImageFilter.enhance,
      processedJpeg: [1],
    );
  });

  tearDown(() async {
    repo.dispose();
    await store.close();
    await dir.delete(recursive: true);
  });

  /// Lance la modification du justificatif depuis une page d'accueil.
  Future<void> edit(WidgetTester tester, {VoidCallback? onDelete}) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => readjustReceipt(
              context,
              repo,
              expense,
              onDelete: () async => onDelete?.call(),
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

  testWidgets(
    'le justificatif s\'ouvre dans la revue, à partir de son original, sans « Ajouter »',
    (tester) async {
      await edit(tester);

      final screen = tester.widget<ReviewScreen>(find.byType(ReviewScreen));
      final page = screen.session.pages.single;
      expect(screen.editing, isTrue);
      expect(page.photoPath, expense.originalPath);
      expect(page.corners, expense.corners);
      expect(page.filter, expense.filter);
      expect(find.text('Ajouter'), findsNothing);
    },
  );

  testWidgets('le filtre choisi dans la revue est enregistré', (tester) async {
    await edit(tester);

    await tester.tap(find.text('Filtres'));
    await settleRealAsync(tester);
    await tester.tap(find.text(ImageFilter.scanBw.label));
    await settleRealAsync(tester);
    await tester.tap(find.text('Enregistrer'));
    await until(tester, () => repo.byId(expense.id)!.filter != expense.filter);

    expect(repo.byId(expense.id)!.filter, ImageFilter.scanBw);
  });

  testWidgets('« Supprimer » demande la suppression de la dépense', (
    tester,
  ) async {
    var deleteAsked = false;
    await edit(tester, onDelete: () => deleteAsked = true);

    await tester.tap(find.text('Supprimer'));
    await settleRealAsync(tester);

    expect(deleteAsked, isTrue);
  });

  testWidgets('enregistrer sans rien changer ne relance pas le traitement', (
    tester,
  ) async {
    await edit(tester);

    await tester.tap(find.text('Enregistrer'));
    await settleRealAsync(tester);
    await until(tester, () => false);

    final kept = repo.byId(expense.id)!;
    expect(kept.status, expense.status);
    expect(File(kept.processedPath!).readAsBytesSync(), [1]);
  });

  testWidgets('revenir en arrière ne modifie pas la dépense', (tester) async {
    var deleteAsked = false;
    await edit(tester, onDelete: () => deleteAsked = true);

    await tester.tap(find.text('Pivoter'));
    await settleRealAsync(tester);
    await tester.pageBack();
    await settleRealAsync(tester);
    await until(tester, () => false);

    final kept = repo.byId(expense.id)!;
    expect(kept.rotation, expense.rotation);
    expect(File(kept.processedPath!).readAsBytesSync(), [1]);
    expect(deleteAsked, isFalse);
  });
}

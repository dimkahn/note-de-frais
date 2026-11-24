import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_de_frais/expense/domain/expense.dart';
import 'package:note_de_frais/scan/domain/quad.dart';
import 'package:note_de_frais/scan/domain/rotation.dart';
import 'package:note_de_frais/scan/domain/scan_session.dart';
import 'package:note_de_frais/scan/ui/adjust_screen.dart' show Compute;
import 'package:note_de_frais/scan/ui/review_screen.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../../support/settle.dart';
import '../data/document_scanner_test.dart' show photoOfReceipt, uniform;

/// Exécution synchrone dans le test (pas d'isolate).
Future<T> _inline<T>(T Function() work) async => work();

void main() {
  late Directory dir;

  setUp(() async => dir = await Directory.systemTemp.createTemp('ndf_review'));
  tearDown(() => dir.delete(recursive: true));

  String save(String name, Uint8List bytes) =>
      (File('${dir.path}/$name.jpg')..writeAsBytesSync(bytes)).path;

  ScanSession session(ScanMode mode, int pages) {
    var s = ScanSession(mode);
    for (var i = 0; i < pages; i++) {
      s = s.withPage(
        CapturedPage(
          photoPath: save('p$i', uniform(600, 800)),
          corners: Quad.inset(0.1),
        ),
      );
    }
    return s;
  }

  /// Ouvre la revue par-dessus une page d'accueil et renvoie le futur de son issue.
  Future<Future<ReviewOutcome?>> open(
    WidgetTester tester,
    ScanSession session, {
    Compute compute = _inline,
  }) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    late Future<ReviewOutcome?> outcome;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => outcome = Navigator.push<ReviewOutcome>(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    ReviewScreen(session: session, compute: compute),
              ),
            ),
            child: const Text('ouvrir'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ouvrir'));
    await tester.pump();
    await settleRealAsync(tester);
    return outcome;
  }

  Future<void> tapTool(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await settleRealAsync(tester);
  }

  /// « Enregistrer », ou « Enregistrer les n pages ».
  Future<void> tapSave(WidgetTester tester) async {
    await tester.tap(find.textContaining('Enregistrer'));
    await settleRealAsync(tester);
  }

  testWidgets('numérote les pages et suit le glissement', (tester) async {
    await open(tester, session(ScanMode.document, 2));
    expect(find.text('Page 1 / 2'), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    await settleRealAsync(tester);

    expect(find.text('Page 2 / 2'), findsOneWidget);
  });

  testWidgets('enregistre une page rendue par page, dans l\'ordre', (
    tester,
  ) async {
    final outcome = await open(tester, session(ScanMode.document, 2));

    await tapSave(tester);

    final saved = (await outcome)! as ReviewSaved;
    expect(saved.pages.map((p) => p.photoPath), [
      '${dir.path}/p0.jpg',
      '${dir.path}/p1.jpg',
    ]);
    expect(
      cv.imdecode(saved.pages.first.processedJpeg, cv.IMREAD_COLOR).isEmpty,
      isFalse,
    );
  });

  testWidgets('détecte le contour des pages prises sans contour', (
    tester,
  ) async {
    final photo = save(
      'ticket',
      photoOfReceipt(1000, 1400, const [
        (240, 210),
        (780, 250),
        (760, 1210),
        (220, 1180),
      ]),
    );
    final outcome = await open(
      tester,
      const ScanSession(ScanMode.ticket)
          .withPage(CapturedPage(photoPath: photo)),
    );

    await tapSave(tester);

    final page = ((await outcome)! as ReviewSaved).pages.single;
    expect(page.quad.topLeft.x, closeTo(0.24, 0.03));
  });

  testWidgets('« Pivoter » tourne la page courante d\'un quart de tour', (
    tester,
  ) async {
    final outcome = await open(tester, session(ScanMode.ticket, 1));

    await tapTool(tester, 'Pivoter');
    await tapSave(tester);

    final page = ((await outcome)! as ReviewSaved).pages.single;
    expect(page.rotation, Rotation.clockwise90);
    final rendered = cv.imdecode(page.processedJpeg, cv.IMREAD_COLOR);
    expect(rendered.cols, greaterThan(rendered.rows));
  });

  testWidgets(
    '« Filtres » montre la page sous chaque filtre et applique le choix',
    (tester) async {
      final outcome = await open(tester, session(ScanMode.ticket, 1));

      await tapTool(tester, 'Filtres');
      for (final filter in ImageFilter.values) {
        expect(
          find.bySemanticsLabel(RegExp('^Aperçu du filtre ${filter.label}')),
          findsOneWidget,
        );
      }
      await tapTool(tester, ImageFilter.scanBw.label);
      await tapSave(tester);

      expect(
        ((await outcome)! as ReviewSaved).pages.single.filter,
        ImageFilter.scanBw,
      );
    },
  );

  testWidgets('« Supprimer » retire la page courante', (tester) async {
    await open(tester, session(ScanMode.document, 2));

    await tapTool(tester, 'Supprimer');

    expect(find.text('Page 1 / 1'), findsOneWidget);
  });

  testWidgets('supprimer la dernière page ramène à la caméra, sans page', (
    tester,
  ) async {
    final outcome = await open(tester, session(ScanMode.ticket, 1));

    await tapTool(tester, 'Supprimer');

    final back = (await outcome)! as ReviewContinue;
    expect(back.session.pages, isEmpty);
    expect(back.session.mode, ScanMode.ticket);
  });

  testWidgets('« Ajouter » ramène à la caméra avec les pages déjà prises', (
    tester,
  ) async {
    final outcome = await open(tester, session(ScanMode.document, 2));

    await tapTool(tester, 'Ajouter');

    final more = (await outcome)! as ReviewContinue;
    expect(more.session.pages, hasLength(2));
    expect(more.addMore, isTrue);
  });

  testWidgets(
    'revenir en arrière sur un ticket le reprend : la page est abandonnée',
    (tester) async {
      final outcome = await open(tester, session(ScanMode.ticket, 1));

      await tester.pageBack();
      await settleRealAsync(tester);

      final back = (await outcome)! as ReviewContinue;
      expect(back.session.pages, isEmpty);
      expect(back.addMore, isFalse);
    },
  );

  testWidgets('revenir en arrière sur un document garde les pages prises', (
    tester,
  ) async {
    final outcome = await open(tester, session(ScanMode.document, 2));

    await tester.pageBack();
    await settleRealAsync(tester);

    final back = (await outcome)! as ReviewContinue;
    expect(back.session.pages, hasLength(2));
    expect(back.addMore, isFalse);
  });

  testWidgets(
    'un échec à l\'enregistrement est signalé et l\'écran reste utilisable',
    (tester) async {
      var failing = false;
      Future<T> compute<T>(T Function() work) async {
        if (failing) throw StateError('rendu impossible');
        return work();
      }

      final outcome = await open(
        tester,
        session(ScanMode.ticket, 1),
        compute: compute,
      );
      failing = true;
      await tapSave(tester);

      expect(find.textContaining('Enregistrement impossible'), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.ancestor(
          of: find.textContaining('Enregistrer'),
          matching: find.byWidgetPredicate((w) => w is FilledButton),
        ),
      );
      expect(button.onPressed, isNotNull);
      failing = false;
      await tapSave(tester);
      expect(await outcome, isA<ReviewSaved>());
    },
  );
}

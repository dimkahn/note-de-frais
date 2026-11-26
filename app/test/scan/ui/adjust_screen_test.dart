import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_de_frais/expense/domain/expense.dart';
import 'package:note_de_frais/scan/domain/quad.dart';
import 'package:note_de_frais/scan/domain/rotation.dart';
import 'package:note_de_frais/scan/ui/adjust_screen.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../../support/settle.dart';
import '../data/document_scanner_test.dart' show photoOfReceipt, uniform;

/// Exécution synchrone dans le test (pas d'isolate).
Future<T> _inline<T>(T Function() work) async => work();

void main() {
  late Directory dir;

  setUp(() async => dir = await Directory.systemTemp.createTemp('ndf_adjust'));
  tearDown(() => dir.delete(recursive: true));

  String save(Uint8List bytes) =>
      (File('${dir.path}/photo.jpg')..writeAsBytesSync(bytes)).path;

  /// Ouvre l'écran par-dessus une page d'accueil et renvoie le futur du résultat.
  Future<Future<ScanResult?>> open(
    WidgetTester tester,
    AdjustScreen screen,
  ) async {
    late Future<ScanResult?> result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => result = Navigator.push<ScanResult>(
              context,
              MaterialPageRoute(builder: (_) => screen),
            ),
            child: const Text('ouvrir'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ouvrir'));
    await tester.pump();
    await settleRealAsync(tester);
    return result;
  }

  testWidgets(
    'propose le contour détecté sur la photo et renvoie le scan validé',
    (tester) async {
      final path = save(
        photoOfReceipt(1000, 1400, const [
          (240, 210),
          (780, 250),
          (760, 1210),
          (220, 1180),
        ]),
      );

      final result = await open(
        tester,
        AdjustScreen(photoPath: path, compute: _inline),
      );
      await tester.tap(find.text('Scan N&B'));
      await tester.pump();
      await tester.tap(find.text('Valider'));
      await settleRealAsync(tester);

      final scan = (await result)!;
      expect(scan.photoPath, path);
      expect(scan.filter, ImageFilter.scanBw);
      expect(scan.quad.topLeft.x, closeTo(0.24, 0.03));
      expect(cv.imdecode(scan.processedJpeg, cv.IMREAD_COLOR).isEmpty, isFalse);
    },
  );

  testWidgets('sans document détecté, reprend le contour vu par la caméra', (
    tester,
  ) async {
    final path = save(uniform(600, 800));
    final live = Quad.inset(0.2);

    final result = await open(
      tester,
      AdjustScreen(photoPath: path, fallbackQuad: live, compute: _inline),
    );
    await tester.tap(find.text('Valider'));
    await settleRealAsync(tester);

    expect((await result)!.quad, live);
  });

  testWidgets('« Pivoter » ajoute un quart de tour au rendu validé', (
    tester,
  ) async {
    final path = save(uniform(600, 800));

    final result = await open(
      tester,
      AdjustScreen(
        photoPath: path,
        initialQuad: Quad.inset(0.1),
        initialRotation: Rotation.clockwise90,
        compute: _inline,
      ),
    );
    await tester.tap(find.byTooltip('Pivoter'));
    await tester.pump();
    await tester.tap(find.byTooltip('Pivoter'));
    await tester.pump();
    await tester.tap(find.text('Valider'));
    await settleRealAsync(tester);

    final scan = (await result)!;
    expect(scan.rotation, Rotation.clockwise270);
    final rendered = cv.imdecode(scan.processedJpeg, cv.IMREAD_COLOR);
    expect(rendered.cols, greaterThan(rendered.rows));
  });

  testWidgets('« Reprendre » abandonne sans résultat', (tester) async {
    final path = save(uniform(600, 800));

    final result = await open(
      tester,
      AdjustScreen(photoPath: path, compute: _inline),
    );
    await tester.tap(find.text('Reprendre'));
    await settleRealAsync(tester);

    expect(await result, isNull);
  });
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_de_frais/scan/domain/page_scanner.dart';
import 'package:note_de_frais/scan/domain/scan_session.dart';
import 'package:note_de_frais/scan/ui/camera_screen.dart';
import 'package:note_de_frais/scan/ui/capture.dart';

import '../../support/settle.dart';
import '../data/document_scanner_test.dart' show uniform;

/// Exécution synchrone dans le test (pas d'isolate).
Future<T> _inline<T>(T Function() work) async => work();

/// Scanner système simulé : rend tour à tour les lots de pages prévus.
final class _FakeScanner implements PageScanner {
  _FakeScanner(this.batches, {this.unavailableAfter});

  final List<List<String>?> batches;

  /// Au-delà de ce nombre de passages, le scanner ne démarre plus.
  final int? unavailableAfter;
  final limits = <int?>[];

  @override
  Future<List<String>?> scan({int? pageLimit}) async {
    if (limits.length == unavailableAfter) {
      throw const PageScannerUnavailable('échec au démarrage');
    }
    limits.add(pageLimit);
    return batches.removeAt(0);
  }
}

final class _UnavailableScanner implements PageScanner {
  @override
  Future<List<String>?> scan({int? pageLimit}) async =>
      throw const PageScannerUnavailable('pas de services Google Play');
}

void main() {
  late Directory dir;

  setUp(() async => dir = await Directory.systemTemp.createTemp('ndf_capture'));
  tearDown(() => dir.delete(recursive: true));

  String page(String name) =>
      (File('${dir.path}/$name.jpg')..writeAsBytesSync(uniform(600, 800))).path;

  /// Lance [start] depuis une page d'accueil et renvoie son futur.
  Future<Future<T>> launch<T>(
    WidgetTester tester,
    Future<T> Function(BuildContext) start,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    late Future<T> result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => result = start(context),
            child: const Text('scanner'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('scanner'));
    await settleRealAsync(tester);
    return result;
  }

  testWidgets(
    'les pages du scanner système passent par la revue puis sont enregistrées',
    (tester) async {
      final p1 = page('p1');
      final scanner = _FakeScanner([
        [p1],
      ]);

      final done = await launch(
        tester,
        (context) => scan(
          context,
          modeLocked: true,
          pageScanner: scanner,
          compute: _inline,
        ),
      );
      await tester.tap(find.textContaining('Enregistrer'));
      await settleRealAsync(tester);

      final result = await done;
      expect(result!.mode, ScanMode.ticket);
      expect(result.pages.single.photoPath, p1);
      expect(scanner.limits, [1]);
    },
  );

  testWidgets('abandon dans le scanner système : rien n\'est scanné', (
    tester,
  ) async {
    final done = await launch(
      tester,
      (context) => scan(
        context,
        modeLocked: true,
        pageScanner: _FakeScanner([null]),
        compute: _inline,
      ),
    );

    expect(await done, isNull);
  });

  testWidgets(
    '« Ajouter » relance le scanner système, sans limite en Document',
    (tester) async {
      final p1 = page('p1'), p2 = page('p2'), p3 = page('p3');
      final scanner = _FakeScanner([
        [p1],
        [p2, p3],
      ]);

      final done = await launch(
        tester,
        (context) => scan(
          context,
          mode: ScanMode.document,
          modeLocked: true,
          pageScanner: scanner,
          compute: _inline,
        ),
      );
      await tester.tap(find.text('Ajouter'));
      await settleRealAsync(tester);
      await tester.tap(find.text('Enregistrer les 3 pages'));
      await settleRealAsync(tester);

      final result = await done;
      expect([for (final p in result!.pages) p.photoPath], [p1, p2, p3]);
      expect(scanner.limits, [null, null]);
    },
  );

  testWidgets(
    'scanner système indisponible : la caméra de l\'application prend le relais',
    (tester) async {
      await launch(
        tester,
        (context) => scan(
          context,
          mode: ScanMode.document,
          modeLocked: true,
          pageScanner: _UnavailableScanner(),
          compute: _inline,
        ),
      );

      final camera = tester.widget<CameraScreen>(find.byType(CameraScreen));
      expect(camera.initialMode, ScanMode.document);
      expect(camera.modeLocked, isTrue);
    },
  );

  Future<Future<ScanCompleted?>> scanDocument(
    WidgetTester tester,
    PageScanner scanner,
  ) => launch(
    tester,
    (context) => scan(
      context,
      mode: ScanMode.document,
      modeLocked: true,
      pageScanner: scanner,
      compute: _inline,
    ),
  );

  Future<void> tapAdd(WidgetTester tester) async {
    await tester.tap(find.text('Ajouter'));
    await settleRealAsync(tester);
    await tester.pumpAndSettle(); // fin de la transition vers la nouvelle revue
  }

  Future<void> tapSave(WidgetTester tester) async {
    await tester.tap(find.text('Enregistrer'));
    await settleRealAsync(tester);
  }

  testWidgets(
    'annuler le scanner en ajoutant des pages garde les pages déjà prises',
    (tester) async {
      final p1 = page('p1');
      final done = await scanDocument(
        tester,
        _FakeScanner([
          [p1],
          null,
        ]),
      );

      await tapAdd(tester);
      await tapSave(tester);

      expect([for (final p in (await done)!.pages) p.photoPath], [p1]);
    },
  );

  testWidgets(
    'scanner indisponible en ajoutant des pages : les pages déjà prises restent',
    (tester) async {
      final p1 = page('p1');
      final done = await scanDocument(
        tester,
        _FakeScanner([
          [p1],
        ], unavailableAfter: 1),
      );

      await tapAdd(tester);

      expect(find.byType(CameraScreen), findsNothing);
      expect(find.text('Scanner indisponible, réessayez'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5)); // le message disparaît
      await tester.pumpAndSettle();
      await tapSave(tester);
      expect([for (final p in (await done)!.pages) p.photoPath], [p1]);
    },
  );
}

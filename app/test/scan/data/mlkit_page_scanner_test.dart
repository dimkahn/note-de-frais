import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_de_frais/scan/data/mlkit_page_scanner.dart';
import 'package:note_de_frais/scan/domain/page_scanner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('google_mlkit_document_scanner');
  final calls = <MethodCall>[];

  void answer(Object? Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return handler(call);
        });
  }

  setUp(calls.clear);
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  Map<String, Object?> optionsSent() =>
      ((calls.first.arguments as Map)['options'] as Map).cast();

  test(
    'rend les pages JPEG, en mode de base, import de la galerie permis',
    () async {
      answer(
        (call) => call.method == 'vision#startDocumentScanner'
            ? {
                'images': ['/cache/a.jpg', '/cache/b.jpg'],
                'pdf': null,
              }
            : null,
      );

      final pages = await const MlKitPageScanner().scan(pageLimit: 1);

      expect(pages, ['/cache/a.jpg', '/cache/b.jpg']);
      expect(optionsSent(), {
        'pageLimit': 1,
        'formats': ['jpeg'],
        'mode': 'base',
        'isGalleryImport': true,
      });
    },
  );

  test('sans limite demandée, accepte de nombreuses pages', () async {
    answer((call) => {'images': <String>[], 'pdf': null});

    await const MlKitPageScanner().scan();

    expect(optionsSent()['pageLimit'], MlKitPageScanner.maxPages);
  });

  test('l\'utilisateur annule : null', () async {
    answer(
      (call) => call.method == 'vision#startDocumentScanner'
          ? throw PlatformException(
              code: 'DocumentScanner',
              message: 'Operation cancelled',
            )
          : null,
    );

    expect(await const MlKitPageScanner().scan(), isNull);
  });

  test('le scanner ne démarre pas : indisponible', () async {
    answer(
      (call) => call.method == 'vision#startDocumentScanner'
          ? throw PlatformException(
              code: 'DocumentScanner',
              message: 'Failed to start document scanner',
            )
          : null,
    );

    expect(
      () => const MlKitPageScanner().scan(),
      throwsA(isA<PageScannerUnavailable>()),
    );
  });

  test('plugin absent : indisponible', () async {
    expect(
      () => const MlKitPageScanner().scan(),
      throwsA(isA<PageScannerUnavailable>()),
    );
  });
}

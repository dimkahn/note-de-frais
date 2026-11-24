import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:note_de_frais/account/data/account_repository.dart';
import 'package:note_de_frais/expense/data/expense_repository.dart';
import 'package:note_de_frais/export/data/export_service.dart';
import 'package:note_de_frais/shared/data/file_store.dart';
import 'package:note_de_frais/shared/data/local_store.dart';
import 'package:note_de_frais/expense/domain/expense.dart';
import 'package:note_de_frais/scan/domain/receipt_parser.dart';
import 'package:note_de_frais/expense/ui/home_screen.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:provider/provider.dart';

import '../../support/fake_biometric_auth.dart';
import '../../support/memory_device_key_store.dart';
import '../../support/memory_session_store.dart';
import '../../support/temp_downloads.dart';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late LocalStore store;
  late ExpenseRepository repo;
  late _FakeSharer sharer;

  setUp(() => sharer = _FakeSharer());

  Expense expense(
    String id,
    String merchant,
    ExpenseCategory c,
    String city,
    String amount,
  ) => Expense(
    id: id,
    merchant: merchant,
    category: c,
    city: city,
    expenseDate: DateTime(2026, 3, 10),
    amountTotal: amount,
    currency: 'EUR',
    status: ProcessingStatus.done,
  );

  Future<void> pumpHome(WidgetTester tester, List<Expense> expenses) async {
    await tester.runAsync(() async {
      await initializeDateFormatting('fr_FR');
      store = await LocalStore.open(
        inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );
      for (final e in expenses) {
        await store.save(e);
      }
      final client = MockClient((_) async => http.Response('[]', 200));
      repo = ExpenseRepository(
        store: store,
        files: FileStore(Directory.systemTemp),
        httpClient: client,
        // Sans compte : tout reste sur l'appareil.
        account: AccountRepository(
          store: store,
          sessions: MemorySessionStore(),
          deviceKeys: MemoryDeviceKeyStore(),
          biometrics: FakeBiometricAuth(available: false),
          httpClient: client,
        ),
        pollInterval: null,
      );
      await repo.load();
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: repo),
          Provider.value(
            value: ExportService(
              sharer: sharer,
              tempDir: Directory.systemTemp,
              downloads: TempDownloads(
                Directory('${Directory.systemTemp.path}/Download'),
              ),
            ),
          ),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pump();
  }

  tearDown(() async {
    repo.dispose();
    await store.close();
  });

  testWidgets('invite à photographier un premier justificatif', (tester) async {
    await pumpHome(tester, []);

    expect(
      find.text('Photographiez votre premier justificatif'),
      findsOneWidget,
    );
    expect(find.textContaining('Touchez Scanner'), findsOneWidget);
  });

  testWidgets('liste les dépenses avec le total', (tester) async {
    await pumpHome(tester, [
      expense('a', 'Le Bistrot', ExpenseCategory.restaurant, 'Paris', '20.00'),
      expense('b', 'Ibis', ExpenseCategory.hotel, 'Lyon', '90.00'),
    ]);

    expect(find.text('Le Bistrot'), findsOneWidget);
    expect(find.text('Ibis'), findsOneWidget);
    expect(find.text('2 dépenses'), findsOneWidget);
    expect(find.text('110,00 €'), findsWidgets);
  });

  testWidgets('montre la part de chaque type dans le total', (tester) async {
    await pumpHome(tester, [
      expense('a', 'Le Bistrot', ExpenseCategory.restaurant, 'Paris', '20.00'),
      expense('b', 'Ibis', ExpenseCategory.hotel, 'Lyon', '90.00'),
    ]);

    expect(find.text('Hôtel 82 %'), findsOneWidget);
    expect(find.text('Restaurant 18 %'), findsOneWidget);
  });

  testWidgets('filtre par type de dépense', (tester) async {
    await pumpHome(tester, [
      expense('a', 'Le Bistrot', ExpenseCategory.restaurant, 'Paris', '20.00'),
      expense('b', 'Ibis', ExpenseCategory.hotel, 'Lyon', '90.00'),
    ]);

    await tester.tap(find.widgetWithText(FilterChip, 'Type'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, 'Hôtel'));
    await tester.pumpAndSettle();

    expect(find.text('Ibis'), findsOneWidget);
    expect(find.text('Le Bistrot'), findsNothing);
  });

  testWidgets('recherche libre', (tester) async {
    await pumpHome(tester, [
      expense('a', 'Le Bistrot', ExpenseCategory.restaurant, 'Paris', '20.00'),
      expense('b', 'Ibis', ExpenseCategory.hotel, 'Lyon', '90.00'),
    ]);

    await tester.enterText(find.byType(SearchBar), 'lyon');
    await tester.pump();

    expect(find.text('Ibis'), findsOneWidget);
    expect(find.text('Le Bistrot'), findsNothing);
  });

  group('sans serveur configuré', () {
    final scanned = Expense.draft(
      id: 's',
      originalPath: '/inexistant/s.jpg',
      filter: ImageFilter.enhance,
    );

    testWidgets('une dépense scannée est à compléter, sans synchro proposée', (
      tester,
    ) async {
      await pumpHome(tester, [scanned]);

      expect(find.text('À compléter'), findsOneWidget);
      expect(find.text('En attente d\'envoi'), findsNothing);
      expect(find.byTooltip('Synchroniser'), findsNothing);
    });

    testWidgets('la fiche invite à la saisie manuelle au lieu d\'attendre', (
      tester,
    ) async {
      await pumpHome(tester, [scanned]);

      await tester.tap(find.text('Justificatif sans nom'));
      await tester.pumpAndSettle();

      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(
        find.textContaining('Analyse automatique indisponible'),
        findsOneWidget,
      );
    });

    testWidgets('la fiche signale un pré-remplissage à vérifier', (
      tester,
    ) async {
      await pumpHome(tester, [
        scanned.withDeviceGuess(
          const ReceiptGuess(merchant: 'Carrefour', amountTotal: '5.70'),
        ),
      ]);

      await tester.tap(find.text('Carrefour'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Lu automatiquement'), findsOneWidget);
      expect(
        find.textContaining('Analyse automatique indisponible'),
        findsNothing,
      );
    });
  });

  testWidgets(
    'sans analyse IA incluse, la fiche le signale et garde les valeurs lues sur l\'appareil',
    (tester) async {
      await pumpHome(tester, [
        expense(
          'n',
          'Carrefour',
          ExpenseCategory.fournitures,
          'Lyon',
          '5.70',
        ).copyWith(status: ProcessingStatus.notIncluded, prefilled: true),
      ]);

      await tester.tap(find.text('Carrefour'));
      await tester.pumpAndSettle();

      expect(find.text('Analyse IA incluse avec Premium'), findsOneWidget);
      expect(find.textContaining('Lu automatiquement'), findsOneWidget);
    },
  );

  testWidgets('exporte le justificatif d\'une dépense en PDF', (tester) async {
    late String processed;
    await tester.runAsync(() async {
      final img = cv.Mat.fromScalar(
        80,
        60,
        cv.MatType.CV_8UC3,
        cv.Scalar(230, 230, 230),
      );
      final (_, bytes) = cv.imencode('.jpg', img);
      img.dispose();
      processed = (File(
        '${Directory.systemTemp.path}/ndf_export_test.jpg',
      )..writeAsBytesSync(bytes)).path;
    });
    await pumpHome(tester, [
      expense(
        'a',
        'Le Bistrot',
        ExpenseCategory.restaurant,
        'Paris',
        '20.00',
      ).copyWith(processedPath: processed),
    ]);
    await tester.tap(find.text('Le Bistrot'));
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

    expect(sharer.shared.single.uri.pathSegments.last, 'Le Bistrot.pdf');
  });

  testWidgets('exporte la note de frais de la liste filtrée', (tester) async {
    await pumpHome(tester, [
      expense('a', 'Le Bistrot', ExpenseCategory.restaurant, 'Paris', '20.00'),
      expense('b', 'Ibis', ExpenseCategory.hotel, 'Lyon', '90.00'),
    ]);

    await tester.tap(find.byTooltip('Exporter la note de frais'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Partager le PDF'));
    for (var i = 0; i < 40 && sharer.shared.isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }

    expect(
      sharer.shared.single.uri.pathSegments.last,
      'Note de frais — mars 2026.pdf',
    );
  });
}

final class _FakeSharer implements FileSharer {
  final shared = <File>[];

  @override
  Future<void> share(List<File> files, {required String subject}) async =>
      shared.addAll(files);
}

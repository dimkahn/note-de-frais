import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:note_de_frais/data/expense_repository.dart';
import 'package:note_de_frais/data/file_store.dart';
import 'package:note_de_frais/data/local_store.dart';
import 'package:note_de_frais/domain/expense.dart';
import 'package:note_de_frais/domain/receipt_parser.dart';
import 'package:note_de_frais/ui/home_screen.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late LocalStore store;
  late ExpenseRepository repo;

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
      repo = ExpenseRepository(
        store: store,
        files: FileStore(Directory.systemTemp),
        httpClient: MockClient((_) async => http.Response('[]', 200)),
        pollInterval: null,
      );
      await repo.load();
    });
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: repo,
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
    expect(find.text('Scanner'), findsOneWidget);
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
}

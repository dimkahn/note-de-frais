import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:note_de_frais/document/data/document_repository.dart';
import 'package:note_de_frais/account/data/account_repository.dart';
import 'package:note_de_frais/expense/data/expense_repository.dart';
import 'package:note_de_frais/export/data/export_service.dart';
import 'package:note_de_frais/shared/data/file_store.dart';
import 'package:note_de_frais/shared/data/local_store.dart';
import 'package:note_de_frais/document/domain/document.dart';
import 'package:note_de_frais/document/ui/document_screen.dart';
import 'package:note_de_frais/expense/domain/expense.dart';
import 'package:note_de_frais/scan/domain/scan_session.dart';
import 'package:note_de_frais/scan/ui/capture.dart';
import 'package:note_de_frais/shell/main_shell.dart';
import 'package:provider/provider.dart';

import '../support/fake_biometric_auth.dart';
import '../support/memory_device_key_store.dart';
import '../support/memory_session_store.dart';
import '../support/temp_downloads.dart';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final class _NoSharer implements FileSharer {
  @override
  Future<void> share(List<File> files, {required String subject}) async {}
}

void main() {
  sqfliteFfiInit();
  late LocalStore store;
  late AccountRepository account;
  late ExpenseRepository expenses;
  late DocumentRepository documents;

  Future<void> pumpShell(WidgetTester tester, {ShellScanner? scanner}) async {
    await tester.runAsync(() async {
      await initializeDateFormatting('fr_FR');
      store = await LocalStore.open(
        inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );
      final files = FileStore(Directory.systemTemp);
      final client = MockClient((_) async => http.Response('[]', 200));
      account = AccountRepository(
        store: store,
        sessions: MemorySessionStore(),
        deviceKeys: MemoryDeviceKeyStore(),
        biometrics: FakeBiometricAuth(available: false),
        httpClient: client,
      );
      await account.load();
      expenses = ExpenseRepository(
        store: store,
        files: files,
        httpClient: client,
        account: account,
        pollInterval: null,
      );
      documents = DocumentRepository(
        store: store,
        files: files,
        httpClient: client,
        account: account,
      );
      await expenses.load();
      await documents.load();
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: account),
          ChangeNotifierProvider.value(value: expenses),
          ChangeNotifierProvider.value(value: documents),
          Provider.value(
            value: ExportService(
              sharer: _NoSharer(),
              tempDir: Directory.systemTemp,
              downloads: TempDownloads(
                Directory('${Directory.systemTemp.path}/Download'),
              ),
            ),
          ),
        ],
        child: MaterialApp(
          home: scanner == null ? const MainShell() : MainShell(scan: scanner),
        ),
      ),
    );
    await tester.pump();
  }

  tearDown(() async {
    expenses.dispose();
    account.dispose();
    documents.dispose();
    await store.close();
  });

  testWidgets('la barre d\'onglets mène aux dépenses, documents et compte', (
    tester,
  ) async {
    await pumpShell(tester);

    expect(
      find.text('Photographiez votre premier justificatif'),
      findsOneWidget,
    );

    await tester.tap(find.text('Documents').last);
    await tester.pumpAndSettle();
    expect(find.text('Aucun document'), findsOneWidget);

    await tester.tap(find.text('Compte').last);
    await tester.pumpAndSettle();
    expect(find.text('Créer un compte'), findsOneWidget);
  });

  testWidgets('un seul bouton Scanner, plus de bouton par onglet', (
    tester,
  ) async {
    await pumpShell(tester);

    expect(find.byTooltip('Scanner'), findsOneWidget);
    expect(find.widgetWithText(FloatingActionButton, 'Scanner'), findsNothing);
    await tester.tap(find.text('Documents').last);
    await tester.pumpAndSettle();
    expect(find.text('Nouveau document'), findsNothing);
  });

  testWidgets(
    'le scan part en mode Ticket depuis Dépenses, Document depuis Documents',
    (tester) async {
      final modes = <ScanMode>[];
      await pumpShell(
        tester,
        scanner: (context, mode) async {
          modes.add(mode);
          return null;
        },
      );

      await tester.tap(find.byTooltip('Scanner'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Documents').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Scanner'));
      await tester.pumpAndSettle();

      expect(modes, [ScanMode.ticket, ScanMode.document]);
    },
  );

  testWidgets('après un ticket, les dépenses s\'affichent', (tester) async {
    await pumpShell(
      tester,
      scanner: (context, mode) async => SavedExpense(
        Expense.draft(
          id: 'e1',
          originalPath: '/o.jpg',
          filter: ImageFilter.enhance,
        ),
      ),
    );
    await tester.tap(find.text('Compte').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Scanner'));
    await tester.pumpAndSettle();

    expect(
      find.text('Photographiez votre premier justificatif'),
      findsOneWidget,
    );
  });

  testWidgets('après un document, sa fiche s\'ouvre', (tester) async {
    late ScannedDocument doc;
    await pumpShell(
      tester,
      scanner: (context, mode) async => SavedDocument(doc),
    );
    doc = (await tester.runAsync(() => documents.create(const [])))!;

    await tester.tap(find.byTooltip('Scanner'));
    await tester.pumpAndSettle();

    expect(find.byType(DocumentScreen), findsOneWidget);
  });
}

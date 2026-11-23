import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:note_de_frais/data/document_repository.dart';
import 'package:note_de_frais/data/account_repository.dart';
import 'package:note_de_frais/data/expense_repository.dart';
import 'package:note_de_frais/data/export_service.dart';
import 'package:note_de_frais/data/file_store.dart';
import 'package:note_de_frais/data/local_store.dart';
import 'package:note_de_frais/ui/main_shell.dart';
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

  testWidgets('la barre d\'onglets mène aux dépenses, documents et compte', (
    tester,
  ) async {
    late LocalStore store;
    late AccountRepository account;
    late ExpenseRepository expenses;
    late DocumentRepository documents;
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
        child: const MaterialApp(home: MainShell()),
      ),
    );
    await tester.pump();

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

    expenses.dispose();
    account.dispose();
    documents.dispose();
    await tester.runAsync(store.close);
  });
}

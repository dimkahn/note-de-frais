import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:intl/date_symbol_data_local.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'data/account_repository.dart';
import 'data/biometric_auth.dart';
import 'data/device_key_store.dart';
import 'data/document_repository.dart';
import 'data/expense_repository.dart';
import 'data/export_service.dart';
import 'data/google_auth.dart';
import 'data/platform_downloads_folder.dart';
import 'data/system_file_sharer.dart';
import 'data/file_store.dart';
import 'data/local_store.dart';
import 'data/server_config.dart';
import 'data/session_store.dart';
import 'scan/mlkit_receipt_text_reader.dart';
import 'ui/launch_screen.dart';
import 'ui/main_shell.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // La page de chargement s'affiche aussitôt ; base, dépenses et documents se chargent derrière.
  runApp(NoteDeFraisApp(services: _start()));
}

/// Ce dont l'interface a besoin, prêt à l'emploi.
typedef AppServices = ({
  AccountRepository account,
  ExpenseRepository expenses,
  DocumentRepository documents,
  ExportService export,
});

Future<AppServices> _start() async {
  await initializeDateFormatting('fr_FR');

  final mobile = Platform.isAndroid || Platform.isIOS;
  if (!mobile) sqfliteFfiInit();
  final factory = mobile ? sqflite.databaseFactory : databaseFactoryFfi;

  final dir = await getApplicationSupportDirectory();
  final store = await LocalStore.open(
    p.join(dir.path, 'notes_de_frais.db'),
    factory: factory,
  );
  final files = FileStore(Directory(p.join(dir.path, 'justificatifs')));
  final httpClient = http.Client();
  final account = AccountRepository(
    store: store,
    sessions: SecureSessionStore(),
    deviceKeys: SecureDeviceKeyStore(),
    biometrics: LocalBiometricAuth(),
    google: googleServerClientId.isEmpty
        ? null
        : PluginGoogleAuth(serverClientId: googleServerClientId),
    httpClient: httpClient,
  );
  await account.load();
  final repo = ExpenseRepository(
    store: store,
    files: files,
    httpClient: httpClient,
    account: account,
    // ML Kit n'existe que sur mobile ; sur desktop, la saisie reste manuelle.
    textReader: mobile ? const MlKitReceiptTextReader() : null,
  );
  final documents = DocumentRepository(
    store: store,
    files: FileStore(Directory(p.join(dir.path, 'documents'))),
    httpClient: httpClient,
    account: account,
  );
  await repo.load();
  await documents.load();
  final export = ExportService(
    sharer: const SystemFileSharer(),
    tempDir: await getTemporaryDirectory(),
    downloads: const PlatformDownloadsFolder(),
  );
  // En arrière-plan : l'app est utilisable immédiatement, même hors-ligne ou sans compte.
  account.refresh();
  repo.sync();
  documents.sync();
  return (
    account: account,
    expenses: repo,
    documents: documents,
    export: export,
  );
}

class NoteDeFraisApp extends StatelessWidget {
  const NoteDeFraisApp({super.key, required this.services});

  final Future<AppServices> services;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Note de frais',
      debugShowCheckedModeBanner: false,
      locale: const Locale('fr', 'FR'),
      supportedLocales: const [Locale('fr', 'FR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      // Les services enveloppent le Navigator : tous les écrans ouverts ensuite y ont accès.
      builder: (context, navigator) => LaunchGate<AppServices>(
        load: services,
        builder: (s) => MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: s.account),
            ChangeNotifierProvider.value(value: s.expenses),
            ChangeNotifierProvider.value(value: s.documents),
            Provider.value(value: s.export),
          ],
          child: navigator!,
        ),
      ),
      home: const MainShell(),
    );
  }
}

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

import 'data/expense_repository.dart';
import 'data/file_store.dart';
import 'data/local_store.dart';
import 'scan/mlkit_receipt_text_reader.dart';
import 'ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
  final repo = ExpenseRepository(
    store: store,
    files: files,
    httpClient: http.Client(),
    // ML Kit n'existe que sur mobile ; sur desktop, la saisie reste manuelle.
    textReader: mobile ? const MlKitReceiptTextReader() : null,
  );
  await repo.load();
  repo.sync(); // en arrière-plan : l'app est utilisable immédiatement, même hors-ligne

  runApp(
    ChangeNotifierProvider.value(value: repo, child: const NoteDeFraisApp()),
  );
}

class NoteDeFraisApp extends StatelessWidget {
  const NoteDeFraisApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF1F6F5C);
    return MaterialApp(
      title: 'Notes de frais',
      debugShowCheckedModeBanner: false,
      locale: const Locale('fr', 'FR'),
      supportedLocales: const [Locale('fr', 'FR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: seed,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

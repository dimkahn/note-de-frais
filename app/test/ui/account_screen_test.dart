import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_de_frais/data/account_repository.dart';
import 'package:note_de_frais/data/expense_repository.dart';
import 'package:note_de_frais/data/file_store.dart';
import 'package:note_de_frais/data/local_store.dart';
import 'package:note_de_frais/ui/account_screen.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/fake_server.dart';
import '../support/fake_biometric_auth.dart';
import '../support/memory_device_key_store.dart';
import '../support/memory_session_store.dart';
import '../support/settle.dart';

void main() {
  sqfliteFfiInit();
  const password = 'mot de passe long';
  late LocalStore store;
  late FakeServer server;
  late AccountRepository account;
  late ExpenseRepository expenses;
  late MemoryDeviceKeyStore deviceKeys;
  late FakeBiometricAuth biometrics;

  Future<void> pumpAccount(
    WidgetTester tester, {
    String serverUrl = 'http://serveur',
    String defaultServerAddress = 'http://defaut:8080',
    bool biometricAvailable = true,
    String? deviceKey,
  }) async {
    server = FakeServer();
    deviceKeys = MemoryDeviceKeyStore(deviceKey);
    biometrics = FakeBiometricAuth(available: biometricAvailable);
    await tester.runAsync(() async {
      store = await LocalStore.open(
        inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );
      account = AccountRepository(
        store: store,
        sessions: MemorySessionStore(),
        deviceKeys: deviceKeys,
        biometrics: biometrics,
        httpClient: server.client,
        defaultServerAddress: defaultServerAddress,
      );
      await account.load();
      await account.saveServerAddress(serverUrl);
      expenses = ExpenseRepository(
        store: store,
        files: FileStore(Directory.systemTemp),
        httpClient: server.client,
        account: account,
        pollInterval: null,
      );
      await expenses.load();
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: account),
          ChangeNotifierProvider.value(value: expenses),
        ],
        child: const MaterialApp(home: AccountScreen()),
      ),
    );
    await tester.pump();
  }

  tearDown(() async {
    expenses.dispose();
    account.dispose();
    await store.close();
  });

  Future<void> submit(
    WidgetTester tester, {
    required String mode,
    required String button,
    required String email,
    required String password,
  }) async {
    await tester.tap(
      find.descendant(
        of: find.byType(SegmentedButton<SignInMode>),
        matching: find.text(mode),
      ),
    );
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextFormField, 'E-mail'), email);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Mot de passe'),
      password,
    );
    await tester.tap(find.widgetWithText(FilledButton, button));
    await settleRealAsync(tester);
  }

  testWidgets(
    'déconnecté, propose connexion et inscription, présente les offres et rappelle que l\'app marche sans compte',
    (tester) async {
      await pumpAccount(tester);

      expect(find.text('Compte'), findsOneWidget);
      expect(
        find.widgetWithText(SegmentedButton<SignInMode>, 'Se connecter'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(SegmentedButton<SignInMode>, 'Créer un compte'),
        findsOneWidget,
      );
      expect(find.text('Gratuit'), findsOneWidget);
      expect(find.textContaining('100 Mo'), findsOneWidget);
      expect(find.text('Premium'), findsOneWidget);
      expect(find.textContaining('1 Go'), findsOneWidget);
      expect(find.textContaining('analyse IA'), findsOneWidget);
      expect(find.text('Bientôt disponible'), findsOneWidget);
      expect(find.textContaining('sans compte'), findsOneWidget);
    },
  );

  testWidgets('le jeton d\'accès n\'est plus demandé', (tester) async {
    await pumpAccount(tester);

    expect(find.textContaining('Jeton'), findsNothing);
  });

  testWidgets('créer un compte affiche l\'e-mail et l\'offre', (tester) async {
    await pumpAccount(tester);

    await submit(
      tester,
      mode: 'Créer un compte',
      button: 'Créer mon compte',
      email: 'alice@example.com',
      password: password,
    );

    expect(account.signedIn, isTrue);
    expect(find.text('alice@example.com'), findsOneWidget);
    expect(find.text('Offre Gratuit'), findsOneWidget);
    expect(find.text('Se déconnecter'), findsOneWidget);
  });

  testWidgets(
    'un mot de passe trop court est signalé sans appeler le serveur',
    (tester) async {
      await pumpAccount(tester);

      await submit(
        tester,
        mode: 'Créer un compte',
        button: 'Créer mon compte',
        email: 'alice@example.com',
        password: 'court',
      );

      expect(find.text('Au moins 10 caractères'), findsOneWidget);
      expect(server.requests, isEmpty);
    },
  );

  testWidgets('des identifiants refusés affichent un message clair', (
    tester,
  ) async {
    await pumpAccount(tester);
    server.accounts['alice@example.com'] = password;

    await submit(
      tester,
      mode: 'Se connecter',
      button: 'Se connecter',
      email: 'alice@example.com',
      password: 'mauvais mot de passe',
    );

    expect(find.text('E-mail ou mot de passe incorrect.'), findsOneWidget);
    expect(account.signedIn, isFalse);
  });

  testWidgets('se déconnecter revient au formulaire', (tester) async {
    await pumpAccount(tester);
    server.accounts['alice@example.com'] = password;
    await submit(
      tester,
      mode: 'Se connecter',
      button: 'Se connecter',
      email: 'alice@example.com',
      password: password,
    );

    await tester.ensureVisible(find.text('Se déconnecter'));
    await tester.tap(find.text('Se déconnecter'));
    await settleRealAsync(tester);

    expect(account.signedIn, isFalse);
    expect(find.widgetWithText(FilledButton, 'Se connecter'), findsOneWidget);
  });

  testWidgets('l\'adresse du serveur se règle dans la section Avancé', (
    tester,
  ) async {
    await pumpAccount(tester, serverUrl: '');

    await tester.scrollUntilVisible(
      find.text('Avancé'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Avancé'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Adresse du serveur'),
      'http://192.168.1.10:8080',
    );
    await tester.ensureVisible(find.text('Enregistrer l\'adresse'));
    await tester.tap(find.text('Enregistrer l\'adresse'));
    await settleRealAsync(tester);

    expect(account.settings.baseUrl, 'http://192.168.1.10:8080');
    expect(
      find.text('Adresse utilisée : http://192.168.1.10:8080'),
      findsOneWidget,
    );
  });

  testWidgets(
    'sans adresse saisie, le champ est vide et l\'adresse par défaut est indiquée',
    (tester) async {
      await pumpAccount(tester, serverUrl: '');

      await tester.scrollUntilVisible(
        find.text('Avancé'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Avancé'));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Adresse du serveur'),
      );
      expect(field.controller!.text, isEmpty);
      expect(
        find.text('Adresse utilisée : http://defaut:8080'),
        findsOneWidget,
      );
    },
  );
  group('connexion par empreinte', () {
    Future<void> signIn(WidgetTester tester) async {
      server.accounts['alice@example.com'] = password;
      await submit(
        tester,
        mode: 'Se connecter',
        button: 'Se connecter',
        email: 'alice@example.com',
        password: password,
      );
    }

    Future<void> tapButton(WidgetTester tester, String label) async {
      await tester.ensureVisible(find.text(label));
      await tester.tap(find.text(label));
      await settleRealAsync(tester);
    }

    testWidgets('sans biométrie sur l\'appareil, elle n\'est pas proposée', (
      tester,
    ) async {
      await pumpAccount(tester, biometricAvailable: false);

      await signIn(tester);

      expect(find.text('Activer la connexion par empreinte'), findsNothing);
    });

    testWidgets(
      'sans biométrie, une clé enregistrée ne propose pas de bouton empreinte',
      (tester) async {
        await pumpAccount(
          tester,
          biometricAvailable: false,
          deviceKey: 'cle-appareil',
        );

        expect(find.text('Se connecter avec l\'empreinte'), findsNothing);
      },
    );

    testWidgets('connecté, on l\'active puis on la désactive', (tester) async {
      await pumpAccount(tester);
      await signIn(tester);

      await tapButton(tester, 'Activer la connexion par empreinte');

      expect(deviceKeys.deviceKey, isNotNull);
      expect(find.text('Activer la connexion par empreinte'), findsNothing);

      await tapButton(tester, 'Désactiver l\'empreinte');

      expect(deviceKeys.deviceKey, isNull);
      expect(server.deviceKeys, isEmpty);
      expect(find.text('Activer la connexion par empreinte'), findsOneWidget);
    });

    testWidgets(
      'déconnecté avec une clé, l\'empreinte connecte et le mot de passe reste possible',
      (tester) async {
        await pumpAccount(tester, deviceKey: 'cle-appareil');
        server.deviceKeys['cle-appareil'] = 'alice@example.com';

        expect(
          find.widgetWithText(FilledButton, 'Se connecter'),
          findsOneWidget,
        );
        await tapButton(tester, 'Se connecter avec l\'empreinte');

        expect(account.signedIn, isTrue);
        expect(find.text('alice@example.com'), findsOneWidget);
      },
    );

    testWidgets(
      'une clé refusée affiche un message et retire le bouton empreinte',
      (tester) async {
        await pumpAccount(tester, deviceKey: 'revoquee');

        await tapButton(tester, 'Se connecter avec l\'empreinte');

        expect(account.signedIn, isFalse);
        expect(find.textContaining('n\'est plus valide'), findsOneWidget);
        expect(find.text('Se connecter avec l\'empreinte'), findsNothing);
      },
    );
  });
}

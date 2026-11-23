import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_de_frais/data/account_repository.dart';
import 'package:note_de_frais/data/document_repository.dart';
import 'package:note_de_frais/data/expense_repository.dart';
import 'package:note_de_frais/data/file_store.dart';
import 'package:note_de_frais/data/local_store.dart';
import 'package:note_de_frais/domain/expense.dart';
import 'package:note_de_frais/domain/quad.dart';
import 'package:note_de_frais/ui/account_screen.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/fake_server.dart';
import '../support/fake_biometric_auth.dart';
import '../support/fake_google_auth.dart';
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
  late DocumentRepository documents;
  late MemoryDeviceKeyStore deviceKeys;
  late FakeBiometricAuth biometrics;

  Future<void> pumpAccount(
    WidgetTester tester, {
    String serverUrl = 'http://serveur',
    String defaultServerAddress = 'http://defaut:8080',
    bool biometricAvailable = true,
    String? deviceKey,
    bool withGoogle = false,
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
        google: withGoogle ? FakeGoogleAuth() : null,
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
      documents = DocumentRepository(
        store: store,
        files: FileStore(Directory.systemTemp),
        httpClient: server.client,
        account: account,
      );
      await documents.load();
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: account),
          ChangeNotifierProvider.value(value: expenses),
          ChangeNotifierProvider.value(value: documents),
        ],
        child: const MaterialApp(home: AccountScreen()),
      ),
    );
    await tester.pump();
  }

  tearDown(() async {
    documents.dispose();
    expenses.dispose();
    account.dispose();
    await store.close();
  });

  /// L'écran se stabilise, puis les synchros que la connexion lance en arrière-plan (dépenses et
  /// documents) se terminent.
  Future<void> settle(WidgetTester tester) async {
    await settleRealAsync(tester);
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      if (!expenses.isSyncing && !documents.isSyncing) break;
    }
  }

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
    await settle(tester);
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

  group('offre et espace en ligne', () {
    const mo = 1024 * 1024;

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

    LinearProgressIndicator usageBar(WidgetTester tester) =>
        tester.widget(find.byType(LinearProgressIndicator));

    testWidgets('affiche la place utilisée sur celle de l\'offre', (
      tester,
    ) async {
      await pumpAccount(tester);
      server.usedBytes = 42 * mo;

      await signIn(tester);

      expect(find.text('42 Mo sur 100 Mo'), findsOneWidget);
      expect(find.text('42 %'), findsOneWidget);
      expect(usageBar(tester).value, closeTo(0.42, 0.001));
      expect(
        usageBar(tester).color,
        isNot(
          Theme.of(tester.element(find.byType(AccountScreen)))
              .colorScheme
              .error,
        ),
      );
    });

    testWidgets(
      'au-delà de 90 %, la barre d\'usage passe en couleur d\'alerte',
      (tester) async {
        await pumpAccount(tester);
        server.usedBytes = 95 * mo;

        await signIn(tester);

        expect(
          usageBar(tester).color,
          Theme.of(tester.element(find.byType(AccountScreen)))
              .colorScheme
              .error,
        );
      },
    );

    testWidgets(
      'en Gratuit, « Passer à Premium » est visible mais bientôt disponible',
      (tester) async {
        await pumpAccount(tester);

        await signIn(tester);

        final upgrade = find.widgetWithText(OutlinedButton, 'Passer à Premium');
        expect(upgrade, findsOneWidget);
        expect(tester.widget<OutlinedButton>(upgrade).onPressed, isNull);
        expect(find.text('Bientôt disponible'), findsOneWidget);
      },
    );

    testWidgets('en Premium, « Passer à Premium » n\'est pas proposé', (
      tester,
    ) async {
      await pumpAccount(tester);
      server.premium.add('alice@example.com');

      await signIn(tester);

      expect(find.text('Offre Premium'), findsOneWidget);
      expect(find.text('Passer à Premium'), findsNothing);
    });

    testWidgets(
      'une dépense refusée faute d\'espace est signalée comme restée sur l\'appareil',
      (tester) async {
        await pumpAccount(tester);
        server.quotaFull = true;
        server.accounts['alice@example.com'] = password;

        // Capture, connexion et synchro en temps réel (base et fichier de la capture).
        await tester.runAsync(() async {
          final photo = File('${Directory.systemTemp.path}/ndf_quota.jpg');
          await photo.writeAsBytes([1, 2, 3]);
          await store.save(
            Expense.draft(
              id: 'quota',
              originalPath: photo.path,
              filter: ImageFilter.enhance,
            ),
          );
          await account.login('alice@example.com', password);
          await expenses.sync();
        });
        await tester.pump();

        expect(find.textContaining('Espace en ligne plein'), findsOneWidget);
        expect(
          find.textContaining('1 dépense reste sur cet appareil'),
          findsOneWidget,
        );
      },
    );
  });

  group('documents refusés faute d\'espace', () {
    Future<void> scanDocument() async {
      final photo = File('${Directory.systemTemp.path}/ndf_quota_doc.jpg');
      await photo.writeAsBytes([1, 2, 3]);
      await documents.create([
        PageCapture(
          photoPath: photo.path,
          corners: Quad.inset(0.1),
          filter: ImageFilter.enhance,
          processedJpeg: [4],
        ),
      ]);
    }

    testWidgets('un document refusé est signalé comme resté sur l\'appareil', (
      tester,
    ) async {
      await pumpAccount(tester);
      server.quotaFull = true;
      server.accounts['alice@example.com'] = password;

      await tester.runAsync(() async {
        await account.login('alice@example.com', password);
        await scanDocument();
      });
      await tester.pump();

      expect(find.textContaining('Espace en ligne plein'), findsOneWidget);
      expect(
        find.textContaining('1 document reste sur cet appareil'),
        findsOneWidget,
      );
    });

    testWidgets('dépenses et documents refusés sont comptés ensemble', (
      tester,
    ) async {
      await pumpAccount(tester);
      server.quotaFull = true;
      server.accounts['alice@example.com'] = password;

      await tester.runAsync(() async {
        final photo = File('${Directory.systemTemp.path}/ndf_quota_both.jpg');
        await photo.writeAsBytes([1, 2, 3]);
        await store.save(
          Expense.draft(
            id: 'quota',
            originalPath: photo.path,
            filter: ImageFilter.enhance,
          ),
        );
        await account.login('alice@example.com', password);
        await expenses.sync();
        await scanDocument();
      });
      await tester.pump();

      expect(find.textContaining('Espace en ligne plein'), findsOneWidget);
      expect(
        find.textContaining('1 dépense et 1 document restent sur cet appareil'),
        findsOneWidget,
      );
    });
  });

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

  group('connexion Google', () {
    const continueWithGoogle = 'Continuer avec Google';

    testWidgets(
      'sans identifiant client Google au build, le bouton n\'est pas affiché',
      (tester) async {
        await pumpAccount(tester);

        expect(find.text(continueWithGoogle), findsNothing);
      },
    );

    testWidgets('connecte au compte Google, affiche le compte et synchronise', (
      tester,
    ) async {
      await pumpAccount(tester, withGoogle: true);
      server.googleIdentities['jeton-google'] = 'alice@gmail.com';

      await tester.ensureVisible(find.text(continueWithGoogle));
      await tester.tap(find.text(continueWithGoogle));
      await settle(tester);

      expect(account.signedIn, isTrue);
      expect(find.text('alice@gmail.com'), findsOneWidget);
      expect(find.text('Activer la connexion par empreinte'), findsOneWidget);
      expect(
        server.requests.map((r) => r.url.path),
        contains('/api/expenses/changes'),
      );
    });

    testWidgets('un refus du serveur s\'affiche sous le formulaire', (
      tester,
    ) async {
      await pumpAccount(tester, withGoogle: true);

      await tester.ensureVisible(find.text(continueWithGoogle));
      await tester.tap(find.text(continueWithGoogle));
      await settle(tester);

      expect(account.signedIn, isFalse);
      expect(find.text('Connexion Google refusée, réessayez.'), findsOneWidget);
    });
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
    await settle(tester);

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
    await settle(tester);

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
      await settle(tester);
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

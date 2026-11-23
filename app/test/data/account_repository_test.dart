import 'package:flutter_test/flutter_test.dart';
import 'package:note_de_frais/data/account_repository.dart';
import 'package:note_de_frais/data/auth_api.dart';
import 'package:note_de_frais/data/local_store.dart';
import 'package:note_de_frais/domain/account.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/fake_server.dart';
import '../support/fake_biometric_auth.dart';
import '../support/memory_device_key_store.dart';
import '../support/memory_session_store.dart';

void main() {
  sqfliteFfiInit();
  const password = 'mot de passe long';
  late LocalStore store;
  late MemorySessionStore sessions;
  late MemoryDeviceKeyStore deviceKeys;
  late FakeBiometricAuth biometrics;
  late FakeServer server;

  AccountRepository newRepository({
    String defaultServerAddress = 'http://defaut:8080',
  }) => AccountRepository(
    store: store,
    sessions: sessions,
    deviceKeys: deviceKeys,
    biometrics: biometrics,
    httpClient: server.client,
    defaultServerAddress: defaultServerAddress,
  );

  setUp(() async {
    store = await LocalStore.open(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    sessions = MemorySessionStore();
    deviceKeys = MemoryDeviceKeyStore();
    biometrics = FakeBiometricAuth();
    server = FakeServer();
  });

  tearDown(() => store.close());

  Future<AccountRepository> withServer() async {
    final repo = newRepository();
    await repo.load();
    await repo.saveServerAddress('http://serveur');
    return repo;
  }

  test(
    'sans session enregistrée, l\'utilisateur n\'est pas connecté',
    () async {
      final repo = newRepository();

      await repo.load();

      expect(repo.signedIn, isFalse);
      expect(repo.connected, isFalse);
    },
  );

  test('l\'adresse du serveur est conservée', () async {
    await (await withServer()).saveServerAddress(' http://serveur:8080 ');

    final reopened = newRepository();
    await reopened.load();

    expect(reopened.settings.baseUrl, 'http://serveur:8080');
  });

  test(
    'sans adresse enregistrée, l\'adresse par défaut du build est utilisée',
    () async {
      final repo = newRepository();

      await repo.load();

      expect(repo.serverAddressOverride, isEmpty);
      expect(repo.settings.baseUrl, 'http://defaut:8080');
    },
  );

  test(
    'effacer l\'adresse enregistrée revient à l\'adresse par défaut du build',
    () async {
      final repo = await withServer();

      await repo.saveServerAddress('  ');

      expect(repo.serverAddressOverride, isEmpty);
      expect(repo.settings.baseUrl, 'http://defaut:8080');
    },
  );

  test('après la connexion, l\'usage de l\'espace en ligne est lu', () async {
    server.accounts['alice@example.com'] = password;
    server.usedBytes = 4096;
    final repo = await withServer();

    await repo.login('alice@example.com', password);

    expect(
      repo.session!.account.usage,
      StorageUsage(usedBytes: 4096, quotaBytes: server.quotaBytes),
    );
  });

  test(
    'un compte non relu (erreur du serveur) n\'empêche pas la connexion',
    () async {
      server.accounts['alice@example.com'] = password;
      server.accountFails = true;
      final repo = await withServer();

      await repo.login('alice@example.com', password);

      expect(repo.connected, isTrue);
      expect(repo.session!.account.usage, isNull);
    },
  );

  test(
    'créer un compte connecte et garde la session dans le stockage sécurisé',
    () async {
      final repo = await withServer();

      await repo.register('alice@example.com', password);

      expect(repo.connected, isTrue);
      expect(repo.session!.account.email, 'alice@example.com');
      expect(sessions.session?.token, repo.session!.token);
    },
  );

  test('la session est restaurée au lancement suivant', () async {
    await (await withServer()).register('alice@example.com', password);

    final reopened = newRepository();
    await reopened.load();

    expect(reopened.connected, isTrue);
    expect(reopened.session!.account.email, 'alice@example.com');
  });

  test(
    'des identifiants refusés laissent déconnecté avec un message',
    () async {
      server.accounts['alice@example.com'] = password;
      final repo = await withServer();

      await expectLater(
        repo.login('alice@example.com', 'mauvais mot de passe'),
        throwsA(isA<AuthException>()),
      );
      expect(repo.signedIn, isFalse);
    },
  );

  test(
    'se connecter sans aucune adresse de serveur est refusé avec un message',
    () async {
      final repo = newRepository(defaultServerAddress: '');
      await repo.load();

      await expectLater(
        repo.login('alice@example.com', password),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            contains('Avancé'),
          ),
        ),
      );
    },
  );

  test('la déconnexion révoque la session sur le serveur et l\'efface de l\'appareil', () async {
    final repo = await withServer();
    await repo.register('alice@example.com', password);
    final token = repo.session!.token;

    await repo.logout();

    expect(repo.signedIn, isFalse);
    expect(sessions.session, isNull);
    expect(server.sessions, isNot(contains(token)));
  });

  test(
    'hors-ligne, la déconnexion efface quand même la session de l\'appareil',
    () async {
      final repo = await withServer();
      await repo.register('alice@example.com', password);
      server.offline = true;

      await repo.logout();

      expect(repo.signedIn, isFalse);
      expect(sessions.session, isNull);
    },
  );

  test(
    'une session refusée par le serveur au rafraîchissement déconnecte',
    () async {
      final repo = await withServer();
      await repo.register('alice@example.com', password);
      server.expireSessions();

      await repo.refresh();

      expect(repo.signedIn, isFalse);
      expect(sessions.session, isNull);
    },
  );

  test('hors-ligne, le rafraîchissement garde la session', () async {
    final repo = await withServer();
    await repo.register('alice@example.com', password);
    server.offline = true;

    await repo.refresh();

    expect(repo.connected, isTrue);
  });

  test('le rafraîchissement met à jour l\'offre du compte', () async {
    final repo = await withServer();
    await repo.register('alice@example.com', password);
    server.premium.add('alice@example.com');

    await repo.refresh();

    expect(repo.session!.account.plan, Plan.premium);
    expect(sessions.session!.account.plan, Plan.premium);
  });
  group('connexion par empreinte', () {
    test('sans biométrie sur l\'appareil, elle n\'est pas proposée', () async {
      biometrics.available = false;

      final repo = await withServer();

      expect(repo.biometricAvailable, isFalse);
    });

    test(
      'avec une biométrie, elle est proposée mais pas encore activée',
      () async {
        final repo = await withServer();

        expect(repo.biometricAvailable, isTrue);
        expect(repo.biometricEnabled, isFalse);
      },
    );

    test(
      'l\'activer après connexion garde la clé émise par le serveur',
      () async {
        final repo = await withServer();
        await repo.register('alice@example.com', password);

        await repo.enableBiometricLogin();

        expect(biometrics.prompts, 1);
        expect(repo.biometricEnabled, isTrue);
        expect(server.deviceKeys.keys, [deviceKeys.deviceKey]);
      },
    );

    test(
      'l\'activation est abandonnée si l\'empreinte n\'est pas reconnue',
      () async {
        final repo = await withServer();
        await repo.register('alice@example.com', password);
        biometrics.succeeds = false;

        await repo.enableBiometricLogin();

        expect(repo.biometricEnabled, isFalse);
        expect(deviceKeys.deviceKey, isNull);
        expect(server.deviceKeys, isEmpty);
      },
    );

    test('une session expirée à l\'activation déconnecte', () async {
      final repo = await withServer();
      await repo.register('alice@example.com', password);
      server.expireSessions();

      await repo.enableBiometricLogin();

      expect(repo.signedIn, isFalse);
      expect(repo.biometricEnabled, isFalse);
    });

    test(
      'la déconnexion conserve la clé, retrouvée au lancement suivant',
      () async {
        final repo = await withServer();
        await repo.register('alice@example.com', password);
        await repo.enableBiometricLogin();

        await repo.logout();
        final reopened = newRepository();
        await reopened.load();

        expect(reopened.signedIn, isFalse);
        expect(reopened.biometricEnabled, isTrue);
        expect(server.deviceKeys, isNotEmpty);
      },
    );

    test('l\'empreinte reconnecte au compte sans mot de passe', () async {
      final repo = await withServer();
      await repo.register('alice@example.com', password);
      await repo.enableBiometricLogin();
      await repo.logout();

      await repo.loginWithBiometrics();

      expect(repo.connected, isTrue);
      expect(repo.session!.account.email, 'alice@example.com');
      expect(sessions.session?.token, repo.session!.token);
    });

    test(
      'la clé n\'est pas lue sans authentification biométrique réussie',
      () async {
        deviceKeys.deviceKey = 'cle-appareil';
        server.deviceKeys['cle-appareil'] = 'alice@example.com';
        final repo = await withServer();
        biometrics.succeeds = false;

        await repo.loginWithBiometrics();

        expect(deviceKeys.reads, 0);
        expect(repo.signedIn, isFalse);
        expect(server.requests, isEmpty);
      },
    );

    test('une clé refusée par le serveur est effacée et un message invite au mot de passe', () async {
      deviceKeys.deviceKey = 'revoquee';
      final repo = await withServer();

      await expectLater(
        repo.loginWithBiometrics(),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            contains('mot de passe'),
          ),
        ),
      );
      expect(repo.signedIn, isFalse);
      expect(repo.biometricEnabled, isFalse);
      expect(deviceKeys.deviceKey, isNull);
    });

    test('l\'activer retient le compte auquel la clé est liée', () async {
      final repo = await withServer();
      await repo.register('alice@example.com', password);

      await repo.enableBiometricLogin();

      expect(deviceKeys.deviceOwner, 'alice@example.com');
    });

    test('se connecter par mot de passe à un autre compte efface la clé de l\'ancien et repropose l\'empreinte', () async {
      server.accounts['bob@example.com'] = password;
      final repo = await withServer();
      await repo.register('alice@example.com', password);
      await repo.enableBiometricLogin();
      await repo.logout();

      await repo.login('bob@example.com', password);

      expect(deviceKeys.deviceKey, isNull);
      expect(repo.biometricEnabled, isFalse);
      expect(repo.biometricAvailable, isTrue);
    });

    test('créer un autre compte efface aussi la clé de l\'ancien', () async {
      final repo = await withServer();
      await repo.register('alice@example.com', password);
      await repo.enableBiometricLogin();
      await repo.logout();

      await repo.register('bob@example.com', password);

      expect(deviceKeys.deviceKey, isNull);
      expect(repo.biometricEnabled, isFalse);
    });

    test(
      'se reconnecter par mot de passe au même compte conserve la clé',
      () async {
        final repo = await withServer();
        await repo.register('alice@example.com', password);
        await repo.enableBiometricLogin();
        await repo.logout();

        await repo.login('alice@example.com', password);

        expect(deviceKeys.deviceKey, isNotNull);
        expect(repo.biometricEnabled, isTrue);
      },
    );

    test('une clé dont le compte est inconnu est effacée à la connexion par mot de passe', () async {
      deviceKeys.deviceKey = 'cle-sans-compte';
      server.accounts['alice@example.com'] = password;
      final repo = await withServer();

      await repo.login('alice@example.com', password);

      expect(deviceKeys.deviceKey, isNull);
      expect(repo.biometricEnabled, isFalse);
    });

    test('la désactiver révoque la clé sur le serveur et l\'efface', () async {
      final repo = await withServer();
      await repo.register('alice@example.com', password);
      await repo.enableBiometricLogin();

      await repo.disableBiometricLogin();

      expect(repo.biometricEnabled, isFalse);
      expect(deviceKeys.deviceKey, isNull);
      expect(server.deviceKeys, isEmpty);
      expect(repo.signedIn, isTrue);
    });

    test('hors-ligne, la désactiver efface quand même la clé', () async {
      final repo = await withServer();
      await repo.register('alice@example.com', password);
      await repo.enableBiometricLogin();
      server.offline = true;

      await repo.disableBiometricLogin();

      expect(repo.biometricEnabled, isFalse);
      expect(deviceKeys.deviceKey, isNull);
    });
  });
}

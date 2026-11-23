import 'package:flutter_test/flutter_test.dart';
import 'package:note_de_frais/data/account_repository.dart';
import 'package:note_de_frais/data/auth_api.dart';
import 'package:note_de_frais/data/local_store.dart';
import 'package:note_de_frais/domain/account.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/fake_server.dart';
import '../support/memory_session_store.dart';

void main() {
  sqfliteFfiInit();
  const password = 'mot de passe long';
  late LocalStore store;
  late MemorySessionStore sessions;
  late FakeServer server;

  AccountRepository newRepository() => AccountRepository(
    store: store,
    sessions: sessions,
    httpClient: server.client,
  );

  setUp(() async {
    store = await LocalStore.open(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    sessions = MemorySessionStore();
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
    'se connecter sans adresse de serveur est refusé avec un message',
    () async {
      final repo = newRepository();
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
}

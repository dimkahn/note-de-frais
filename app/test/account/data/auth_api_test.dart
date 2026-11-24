import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:note_de_frais/account/data/auth_api.dart';
import 'package:note_de_frais/expense/data/expense_api.dart';
import 'package:note_de_frais/account/domain/account.dart';

AuthApi _api(MockClientHandler handler) => AuthApi(
  client: MockClient(handler),
  settings: () => const ServerSettings(baseUrl: 'http://serveur:8080/'),
);

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

const _alice = {'email': 'alice@example.com', 'plan': 'FREE'};

void main() {
  test(
    'l\'inscription envoie l\'e-mail et le mot de passe et rend la session',
    () async {
      late http.Request seen;
      final api = _api((r) async {
        seen = r;
        return _json({'token': 'jeton', 'account': _alice}, 201);
      });

      final session = await api.register(
        'alice@example.com',
        'mot de passe long',
      );

      expect(seen.method, 'POST');
      expect(seen.url.toString(), 'http://serveur:8080/api/auth/register');
      expect(jsonDecode(seen.body), {
        'email': 'alice@example.com',
        'password': 'mot de passe long',
      });
      expect(session.token, 'jeton');
      expect(
        session.account,
        const Account(email: 'alice@example.com', plan: Plan.free),
      );
    },
  );

  test('la connexion rend la session', () async {
    late http.Request seen;
    final api = _api((r) async {
      seen = r;
      return _json({'token': 'jeton', 'account': _alice});
    });

    final session = await api.login('alice@example.com', 'mot de passe long');

    expect(seen.url.path, '/api/auth/login');
    expect(session.token, 'jeton');
  });

  test('des identifiants refusés donnent un message clair', () async {
    final api = _api((_) async => _json({'detail': 'x'}, 401));

    expect(
      api.login('alice@example.com', 'mauvais mot de passe'),
      throwsA(
        isA<AuthException>().having(
          (e) => e.message,
          'message',
          'E-mail ou mot de passe incorrect.',
        ),
      ),
    );
  });

  test('un e-mail déjà utilisé donne un message clair', () async {
    final api = _api((_) async => _json({'detail': 'x'}, 409));

    expect(
      api.register('alice@example.com', 'mot de passe long'),
      throwsA(
        isA<AuthException>().having(
          (e) => e.message,
          'message',
          'Un compte existe déjà avec cette adresse e-mail.',
        ),
      ),
    );
  });

  test(
    'une inscription refusée pour sa forme donne un message clair',
    () async {
      final api = _api((_) async => _json({'detail': 'x'}, 400));

      expect(
        api.register('pas-un-email', 'court'),
        throwsA(isA<AuthException>()),
      );
    },
  );

  test('sans réseau, l\'erreur est une OfflineException', () async {
    final api = _api((_) async => throw const SocketException('pas de réseau'));

    expect(
      api.login('a@b.fr', 'mot de passe long'),
      throwsA(isA<OfflineException>()),
    );
  });

  test('la déconnexion présente le jeton de session', () async {
    late http.Request seen;
    final api = _api((r) async {
      seen = r;
      return http.Response('', 204);
    });

    await api.logout('jeton');

    expect(seen.url.path, '/api/auth/logout');
    expect(seen.headers['Authorization'], 'Bearer jeton');
  });

  test('le compte connecté est relu avec le jeton de session', () async {
    late http.Request seen;
    final api = _api((r) async {
      seen = r;
      return _json({'email': 'alice@example.com', 'plan': 'PREMIUM'});
    });

    final account = await api.account('jeton');

    expect(seen.url.path, '/api/account');
    expect(seen.headers['Authorization'], 'Bearer jeton');
    expect(account.plan, Plan.premium);
  });

  test(
    'une session expirée est signalée par une UnauthorizedException',
    () async {
      final api = _api((_) async => http.Response('', 401));

      expect(api.account('perime'), throwsA(isA<UnauthorizedException>()));
    },
  );
  test(
    'la clé d\'appareil est demandée avec le jeton de session et un libellé',
    () async {
      late http.Request seen;
      final api = _api((r) async {
        seen = r;
        return _json({'deviceKey': 'cle-appareil'}, 201);
      });

      final deviceKey = await api.registerDevice('jeton', 'android');

      expect(seen.method, 'POST');
      expect(seen.url.path, '/api/auth/devices');
      expect(seen.headers['Authorization'], 'Bearer jeton');
      expect(jsonDecode(seen.body), {'label': 'android'});
      expect(deviceKey, 'cle-appareil');
    },
  );

  test('la connexion par clé d\'appareil rend une nouvelle session', () async {
    late http.Request seen;
    final api = _api((r) async {
      seen = r;
      return _json({'token': 'jeton', 'account': _alice});
    });

    final session = await api.deviceLogin('cle-appareil');

    expect(seen.method, 'POST');
    expect(seen.url.path, '/api/auth/device-login');
    expect(seen.headers['Authorization'], isNull);
    expect(jsonDecode(seen.body), {'deviceKey': 'cle-appareil'});
    expect(session.token, 'jeton');
    expect(session.account.email, 'alice@example.com');
  });

  test(
    'une clé d\'appareil refusée est signalée par une UnauthorizedException',
    () async {
      final api = _api((_) async => http.Response('', 401));

      expect(
        api.deviceLogin('revoquee'),
        throwsA(isA<UnauthorizedException>()),
      );
    },
  );

  test(
    'la révocation présente le jeton de session et la clé de l\'appareil',
    () async {
      late http.Request seen;
      final api = _api((r) async {
        seen = r;
        return http.Response('', 204);
      });

      await api.revokeDevice('jeton', 'cle-appareil');

      expect(seen.method, 'DELETE');
      expect(seen.url.path, '/api/auth/devices/current');
      expect(seen.headers['Authorization'], 'Bearer jeton');
      expect(jsonDecode(seen.body), {'deviceKey': 'cle-appareil'});
    },
  );

  group('connexion Google', () {
    test('envoie le jeton d\'identité Google et rend la session', () async {
      late http.Request seen;
      final api = _api((r) async {
        seen = r;
        return _json({'token': 'jeton', 'account': _alice});
      });

      final session = await api.googleLogin('jeton-google');

      expect(seen.method, 'POST');
      expect(seen.url.path, '/api/auth/google');
      expect(jsonDecode(seen.body), {'idToken': 'jeton-google'});
      expect(session.token, 'jeton');
      expect(session.account.email, 'alice@example.com');
    });

    test('un jeton refusé par le serveur donne un message clair', () async {
      final api = _api((_) async => _json({'status': 401}, 401));

      expect(
        api.googleLogin('falsifie'),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            'Connexion Google refusée, réessayez.',
          ),
        ),
      );
    });

    test(
      'un compte que Google ne peut pas ouvrir affiche le motif du serveur',
      () async {
        final api = _api(
          (_) async => _json({
            'status': 403,
            'detail': 'Adresse e-mail Google non vérifiée',
          }, 403),
        );

        expect(
          api.googleLogin('jeton-google'),
          throwsA(
            isA<AuthException>().having(
              (e) => e.message,
              'message',
              'Adresse e-mail Google non vérifiée.',
            ),
          ),
        );
      },
    );

    test(
      'une connexion Google indisponible sur le serveur l\'explique',
      () async {
        final api = _api((_) async => _json({'status': 503}, 503));

        expect(
          api.googleLogin('jeton-google'),
          throwsA(
            isA<AuthException>().having(
              (e) => e.message,
              'message',
              'Connexion Google indisponible sur ce serveur pour le moment.',
            ),
          ),
        );
      },
    );
  });

  test('la connexion par mot de passe d\'un compte Google invite à continuer avec Google', () async {
    final api = _api(
      (_) async => _json({'status': 401, 'code': 'PASSWORD_NOT_SET'}, 401),
    );

    expect(
      api.login('alice@gmail.com', 'mot de passe long'),
      throwsA(
        isA<AuthException>().having(
          (e) => e.message,
          'message',
          'Ce compte n\'a pas de mot de passe : utilisez « Continuer avec Google ».',
        ),
      ),
    );
  });

  test(
    'un motif de refus déjà ponctué n\'est pas doublé d\'un point',
    () async {
      final api = _api(
        (_) async => _json({'status': 403, 'detail': 'Compte déjà lié.'}, 403),
      );

      expect(
        api.googleLogin('jeton-google'),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            'Compte déjà lié.',
          ),
        ),
      );
    },
  );

  test(
    'un refus de connexion sans corps lisible reste « mot de passe incorrect »',
    () async {
      final api = _api((_) async => http.Response('', 401));

      expect(
        api.login('alice@example.com', 'mot de passe long'),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            'E-mail ou mot de passe incorrect.',
          ),
        ),
      );
    },
  );
}

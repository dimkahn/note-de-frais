import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:note_de_frais/account/data/auth_api.dart';
import 'package:note_de_frais/account/data/google_auth.dart';

/// Frontière système : le compte Google de l'appareil, simulé.
class _FakeGoogleSignIn implements GoogleSignIn {
  final initializedWith = <String?>[];
  String? idToken = 'jeton-google';
  Object? failure;
  Object? initFailure;

  @override
  Future<void> initialize({
    String? clientId,
    String? serverClientId,
    String? nonce,
    String? hostedDomain,
  }) async {
    initializedWith.add(serverClientId);
    final f = initFailure;
    initFailure = null;
    if (f != null) throw f;
  }

  @override
  Future<GoogleSignInAccount> authenticate({
    List<String> scopeHint = const <String>[],
  }) async {
    if (failure != null) throw failure!;
    return _FakeAccount(idToken);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAccount implements GoogleSignInAccount {
  _FakeAccount(this._idToken);

  final String? _idToken;

  @override
  GoogleSignInAuthentication get authentication =>
      GoogleSignInAuthentication(idToken: _idToken);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _FakeGoogleSignIn system;
  late PluginGoogleAuth google;

  setUp(() {
    system = _FakeGoogleSignIn();
    google = PluginGoogleAuth(
      serverClientId: 'serveur.apps.googleusercontent.com',
      signIn: system,
    );
  });

  test('rend le jeton d\'identité destiné au serveur, après une seule initialisation', () async {
    final first = await google.idToken();
    await google.idToken();

    expect(first, 'jeton-google');
    expect(system.initializedWith, ['serveur.apps.googleusercontent.com']);
  });

  test('une annulation par l\'utilisateur rend null', () async {
    system.failure = const GoogleSignInException(
      code: GoogleSignInExceptionCode.canceled,
    );

    expect(await google.idToken(), isNull);
  });

  test('un échec de Google donne un message clair', () async {
    system.failure = const GoogleSignInException(
      code: GoogleSignInExceptionCode.clientConfigurationError,
    );

    expect(
      google.idToken(),
      throwsA(
        isA<AuthException>().having(
          (e) => e.message,
          'message',
          'Connexion Google impossible sur cet appareil, réessayez plus tard.',
        ),
      ),
    );
  });

  test(
    'un compte Google sans jeton d\'identité donne un message clair',
    () async {
      system.idToken = null;

      expect(google.idToken(), throwsA(isA<AuthException>()));
    },
  );

  test(
    'une initialisation échouée est retentée à la demande suivante',
    () async {
      system.initFailure = const GoogleSignInException(
        code: GoogleSignInExceptionCode.unknownError,
      );
      await expectLater(google.idToken(), throwsA(isA<AuthException>()));

      final token = await google.idToken();

      expect(token, 'jeton-google');
      expect(system.initializedWith, hasLength(2));
    },
  );

  test(
    'une erreur inattendue du plugin donne aussi un message clair',
    () async {
      system.failure = PlatformException(code: 'sign_in_failed');

      expect(google.idToken(), throwsA(isA<AuthException>()));
    },
  );
}

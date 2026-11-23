import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'auth_api.dart';

/// Connexion au compte Google de l'appareil, pour obtenir un jeton d'identité destiné au serveur.
abstract interface class GoogleAuth {
  /// Jeton d'identité Google ; `null` si l'utilisateur a annulé. Échec → [AuthException].
  Future<String?> idToken();
}

/// Compte Google via `google_sign_in`.
final class PluginGoogleAuth implements GoogleAuth {
  PluginGoogleAuth({required this.serverClientId, GoogleSignIn? signIn})
    : _signIn = signIn ?? GoogleSignIn.instance;

  /// Identifiant client OAuth « web » du serveur : l'audience du jeton rendu.
  final String serverClientId;
  final GoogleSignIn _signIn;
  Future<void>? _initialized;

  static const _failure =
      'Connexion Google impossible sur cet appareil, réessayez plus tard.';

  @override
  Future<String?> idToken() async {
    try {
      await (_initialized ??= _signIn.initialize(
        serverClientId: serverClientId,
      ));
      final idToken = (await _signIn.authenticate()).authentication.idToken;
      if (idToken == null) throw AuthException(_failure);
      return idToken;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      _failed('Connexion Google interrompue : ${e.code.name}');
    } on PlatformException catch (e) {
      _failed('Connexion Google impossible : ${e.code}');
    }
  }

  /// Une initialisation échouée sera retentée à la demande suivante.
  Never _failed(String log) {
    _initialized = null;
    debugPrint(log);
    throw AuthException(_failure);
  }
}

import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

/// Authentification biométrique de l'appareil (empreinte, visage), sans repli sur le code.
abstract interface class BiometricAuth {
  /// Une biométrie est enregistrée sur l'appareil et utilisable par l'app.
  Future<bool> isAvailable();

  /// `true` si l'utilisateur s'est authentifié ; `false` s'il a annulé ou échoué.
  Future<bool> authenticate(String reason);
}

/// Biométrie du système via `local_auth`.
final class LocalBiometricAuth implements BiometricAuth {
  LocalBiometricAuth([LocalAuthentication? auth])
    : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> isAvailable() async {
    try {
      return await _auth.canCheckBiometrics &&
          (await _auth.getAvailableBiometrics()).isNotEmpty;
    } on Exception catch (e) {
      // Plateforme sans biométrie (desktop, émulateur…) : l'option n'est pas proposée.
      debugPrint('Biométrie indisponible : $e');
      return false;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
      );
    } on LocalAuthException catch (e) {
      debugPrint('Authentification biométrique interrompue : ${e.code.name}');
      return false;
    }
  }
}

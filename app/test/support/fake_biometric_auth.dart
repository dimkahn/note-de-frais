import 'package:note_de_frais/data/biometric_auth.dart';

/// Double de la biométrie de l'appareil : disponible ou non, réussie ou non.
final class FakeBiometricAuth implements BiometricAuth {
  FakeBiometricAuth({this.available = true, this.succeeds = true});

  bool available;
  bool succeeds;
  var prompts = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> authenticate(String reason) async {
    prompts++;
    return succeeds;
  }
}

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:note_de_frais/account/data/biometric_auth.dart';

/// Frontière système : la biométrie de l'appareil, simulée.
class _FakeLocalAuthentication implements LocalAuthentication {
  bool supportsBiometrics = true;
  List<BiometricType> enrolled = [BiometricType.fingerprint];
  Object? failure;
  bool succeeds = true;
  bool? biometricOnly;
  String? reason;

  @override
  Future<bool> get canCheckBiometrics async => supportsBiometrics;

  @override
  Future<List<BiometricType>> getAvailableBiometrics() async {
    if (failure != null) throw failure!;
    return enrolled;
  }

  @override
  Future<bool> authenticate({
    required String localizedReason,
    Iterable<Object?> authMessages = const [],
    bool biometricOnly = false,
    bool sensitiveTransaction = true,
    bool persistAcrossBackgrounding = false,
  }) async {
    this.biometricOnly = biometricOnly;
    reason = localizedReason;
    if (failure != null) throw failure!;
    return succeeds;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _FakeLocalAuthentication system;
  late LocalBiometricAuth biometrics;

  setUp(() {
    system = _FakeLocalAuthentication();
    biometrics = LocalBiometricAuth(system);
  });

  test('disponible quand une empreinte est enregistrée', () async {
    expect(await biometrics.isAvailable(), isTrue);
  });

  test('indisponible sans capteur biométrique', () async {
    system.supportsBiometrics = false;

    expect(await biometrics.isAvailable(), isFalse);
  });

  test('indisponible sans biométrie enregistrée', () async {
    system.enrolled = [];

    expect(await biometrics.isAvailable(), isFalse);
  });

  test('indisponible quand la plateforme ne gère pas la biométrie', () async {
    system.failure = MissingPluginException();

    expect(await biometrics.isAvailable(), isFalse);
  });

  test(
    'l\'authentification exige la biométrie seule, sans code de repli',
    () async {
      final ok = await biometrics.authenticate('Connexion à votre compte');

      expect(ok, isTrue);
      expect(system.biometricOnly, isTrue);
      expect(system.reason, 'Connexion à votre compte');
    },
  );

  test('une authentification refusée rend false', () async {
    system.succeeds = false;

    expect(await biometrics.authenticate('Connexion'), isFalse);
  });

  test('une annulation par l\'utilisateur rend false', () async {
    system.failure = const LocalAuthException(
      code: LocalAuthExceptionCode.userCanceled,
    );

    expect(await biometrics.authenticate('Connexion'), isFalse);
  });
}

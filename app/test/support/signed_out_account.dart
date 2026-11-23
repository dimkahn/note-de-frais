import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:note_de_frais/data/account_repository.dart';
import 'package:note_de_frais/data/local_store.dart';

import 'fake_biometric_auth.dart';
import 'memory_device_key_store.dart';
import 'memory_session_store.dart';

/// Client HTTP qui ne devrait jamais être appelé : sans compte, rien ne part vers le serveur.
final noServer = MockClient(
  (request) async => throw StateError('Appel serveur inattendu : $request'),
);

/// Compte sans session : l'app fonctionne sur l'appareil seulement.
Future<AccountRepository> signedOutAccount(
  LocalStore store, {
  http.Client? client,
}) async {
  final account = AccountRepository(
    store: store,
    sessions: MemorySessionStore(),
    deviceKeys: MemoryDeviceKeyStore(),
    biometrics: FakeBiometricAuth(available: false),
    httpClient: client ?? noServer,
  );
  await account.load();
  return account;
}

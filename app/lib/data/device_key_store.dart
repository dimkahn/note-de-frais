import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Clé d'appareil de la connexion par empreinte : un secret longue durée, lié au compte
/// qui l'a activée.
abstract interface class DeviceKeyStore {
  /// Une clé est enregistrée, sans la lire.
  Future<bool> exists();

  Future<String?> read();

  /// E-mail du compte auquel la clé est liée (inconnu pour une clé enregistrée sans compte).
  Future<String?> owner();

  Future<void> write(String deviceKey, {required String owner});

  Future<void> clear();
}

/// Clé dans le stockage sécurisé du système (Keystore Android, trousseau iOS…).
final class SecureDeviceKeyStore implements DeviceKeyStore {
  SecureDeviceKeyStore([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;

  static const _key = 'device.key';
  static const _owner = 'device.owner';

  @override
  Future<bool> exists() => _storage.containsKey(key: _key);

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<String?> owner() => _storage.read(key: _owner);

  @override
  Future<void> write(String deviceKey, {required String owner}) async {
    // Propriétaire d'abord : une clé n'existe jamais sans son compte.
    await _storage.write(key: _owner, value: owner);
    await _storage.write(key: _key, value: deviceKey);
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _key);
    await _storage.delete(key: _owner);
  }
}

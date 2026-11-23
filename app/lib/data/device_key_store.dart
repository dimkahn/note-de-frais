import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Clé d'appareil de la connexion par empreinte : un secret longue durée.
abstract interface class DeviceKeyStore {
  /// Une clé est enregistrée, sans la lire.
  Future<bool> exists();

  Future<String?> read();

  Future<void> write(String deviceKey);

  Future<void> clear();
}

/// Clé dans le stockage sécurisé du système (Keystore Android, trousseau iOS…).
final class SecureDeviceKeyStore implements DeviceKeyStore {
  SecureDeviceKeyStore([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;

  static const _key = 'device.key';

  @override
  Future<bool> exists() => _storage.containsKey(key: _key);

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String deviceKey) =>
      _storage.write(key: _key, value: deviceKey);

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

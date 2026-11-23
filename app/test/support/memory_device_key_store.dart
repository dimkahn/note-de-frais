import 'package:note_de_frais/data/device_key_store.dart';

/// Double du stockage sécurisé de la clé d'appareil : compte les lectures de la clé.
final class MemoryDeviceKeyStore implements DeviceKeyStore {
  MemoryDeviceKeyStore([this.deviceKey, this.deviceOwner]);

  String? deviceKey;

  /// E-mail du compte qui a activé la clé.
  String? deviceOwner;
  var reads = 0;

  @override
  Future<bool> exists() async => deviceKey != null;

  @override
  Future<String?> read() async {
    reads++;
    return deviceKey;
  }

  @override
  Future<String?> owner() async => deviceOwner;

  @override
  Future<void> write(String deviceKey, {required String owner}) async {
    this.deviceKey = deviceKey;
    deviceOwner = owner;
  }

  @override
  Future<void> clear() async {
    deviceKey = null;
    deviceOwner = null;
  }
}

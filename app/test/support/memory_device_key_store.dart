import 'package:note_de_frais/data/device_key_store.dart';

/// Double du stockage sécurisé de la clé d'appareil : compte les lectures de la clé.
final class MemoryDeviceKeyStore implements DeviceKeyStore {
  MemoryDeviceKeyStore([this.deviceKey]);

  String? deviceKey;
  var reads = 0;

  @override
  Future<bool> exists() async => deviceKey != null;

  @override
  Future<String?> read() async {
    reads++;
    return deviceKey;
  }

  @override
  Future<void> write(String deviceKey) async => this.deviceKey = deviceKey;

  @override
  Future<void> clear() async => deviceKey = null;
}

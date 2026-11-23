import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_de_frais/data/device_key_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('sans clé enregistrée, rien n\'existe ni n\'est relu', () async {
    final store = SecureDeviceKeyStore();

    expect(await store.exists(), isFalse);
    expect(await store.read(), isNull);
  });

  test('une clé enregistrée existe et est relue telle quelle', () async {
    await SecureDeviceKeyStore().write('cle-appareil');

    final store = SecureDeviceKeyStore();

    expect(await store.exists(), isTrue);
    expect(await store.read(), 'cle-appareil');
  });

  test('l\'effacement supprime la clé', () async {
    final store = SecureDeviceKeyStore();
    await store.write('cle-appareil');

    await store.clear();

    expect(await store.exists(), isFalse);
    expect(await store.read(), isNull);
  });
}

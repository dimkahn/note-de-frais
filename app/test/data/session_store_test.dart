import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_de_frais/data/session_store.dart';
import 'package:note_de_frais/domain/account.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const session = Session(
    token: 'jeton',
    account: Account(email: 'alice@example.com', plan: Plan.free),
  );

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('sans session enregistrée, rien n\'est relu', () async {
    final store = SecureSessionStore();

    expect(await store.read(), isNull);
  });

  test('une session enregistrée est relue telle quelle', () async {
    await SecureSessionStore().write(session);

    final reread = await SecureSessionStore().read();

    expect(reread?.token, 'jeton');
    expect(reread?.account, session.account);
  });

  test('l\'effacement supprime la session', () async {
    final store = SecureSessionStore();
    await store.write(session);

    await store.clear();

    expect(await store.read(), isNull);
  });
}

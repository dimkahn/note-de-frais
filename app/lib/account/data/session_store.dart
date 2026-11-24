import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/account.dart';

/// Conservation de la session entre deux lancements de l'app.
abstract interface class SessionStore {
  Future<Session?> read();

  Future<void> write(Session session);

  Future<void> clear();
}

/// Session dans le stockage sécurisé du système (Keystore Android, trousseau iOS…).
final class SecureSessionStore implements SessionStore {
  SecureSessionStore([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;

  static const _token = 'session.token';
  static const _email = 'session.email';
  static const _plan = 'session.plan';

  @override
  Future<Session?> read() async {
    final token = await _storage.read(key: _token);
    final email = await _storage.read(key: _email);
    if (token == null || email == null) return null;
    return Session(
      token: token,
      account: Account(
        email: email,
        plan: Plan.fromCode(await _storage.read(key: _plan)),
      ),
    );
  }

  @override
  Future<void> write(Session session) async {
    await _storage.write(key: _token, value: session.token);
    await _storage.write(key: _email, value: session.account.email);
    await _storage.write(key: _plan, value: session.account.plan.code);
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _token);
    await _storage.delete(key: _email);
    await _storage.delete(key: _plan);
  }
}

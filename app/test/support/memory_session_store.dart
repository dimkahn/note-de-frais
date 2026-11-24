import 'package:note_de_frais/account/data/session_store.dart';
import 'package:note_de_frais/account/domain/account.dart';

/// Double du stockage sécurisé : la session reste en mémoire.
final class MemorySessionStore implements SessionStore {
  MemorySessionStore([this.session]);

  Session? session;

  @override
  Future<Session?> read() async => session;

  @override
  Future<void> write(Session session) async => this.session = session;

  @override
  Future<void> clear() async => session = null;
}

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../domain/account.dart';
import 'auth_api.dart';
import 'expense_api.dart';
import 'local_store.dart';
import 'session_store.dart';

/// Connexion au serveur : son adresse et la session du compte. Sans session, l'app reste
/// pleinement utilisable sur l'appareil.
class AccountRepository extends ChangeNotifier {
  AccountRepository({
    required this._store,
    required this._sessions,
    required http.Client httpClient,
  }) {
    _api = AuthApi(client: httpClient, settings: () => _settings);
  }

  final LocalStore _store;
  final SessionStore _sessions;
  late final AuthApi _api;

  ServerSettings _settings = const ServerSettings(baseUrl: '');
  Session? _session;

  ServerSettings get settings => _settings;

  Session? get session => _session;

  bool get signedIn => _session != null;

  /// Synchronisation possible : un serveur et une session.
  bool get connected => _settings.isConfigured && signedIn;

  Future<void> load() async {
    _settings = ServerSettings(baseUrl: await _store.setting('baseUrl') ?? '');
    _session = await _sessions.read();
    notifyListeners();
  }

  Future<void> saveServerAddress(String baseUrl) async {
    final trimmed = baseUrl.trim();
    await _store.setSetting('baseUrl', trimmed);
    _settings = ServerSettings(baseUrl: trimmed);
    notifyListeners();
  }

  Future<void> register(String email, String password) =>
      _open(() => _api.register(email.trim(), password));

  Future<void> login(String email, String password) =>
      _open(() => _api.login(email.trim(), password));

  /// Efface la session de l'appareil, puis la révoque sur le serveur si possible.
  /// Les données locales sont conservées.
  Future<void> logout() async {
    final token = _session?.token;
    await expire();
    if (token == null || !_settings.isConfigured) return;
    try {
      await _api.logout(token);
    } on Exception catch (e) {
      // Hors-ligne ou serveur en erreur : la session expirera d'elle-même côté serveur.
      debugPrint('Révocation de la session impossible : $e');
    }
  }

  /// Relit le compte sur le serveur (offre à jour) ; une session refusée déconnecte.
  Future<void> refresh() async {
    final current = _session;
    if (current == null || !_settings.isConfigured) return;
    try {
      final account = await _api.account(current.token);
      await _keep(current.copyWith(account: account));
    } on UnauthorizedException {
      await expire();
    } on OfflineException catch (e) {
      debugPrint('Compte non rafraîchi (hors-ligne) : $e');
    }
  }

  /// Session refusée par le serveur : retour à l'état déconnecté.
  Future<void> expire() async {
    await _sessions.clear();
    _session = null;
    notifyListeners();
  }

  Future<void> _open(Future<Session> Function() authenticate) async {
    if (!_settings.isConfigured) {
      throw AuthException(
        'Renseignez d\'abord l\'adresse du serveur (section « Avancé »).',
      );
    }
    await _keep(await authenticate());
  }

  Future<void> _keep(Session session) async {
    await _sessions.write(session);
    _session = session;
    notifyListeners();
  }
}

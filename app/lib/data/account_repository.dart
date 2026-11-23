import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../domain/account.dart';
import 'auth_api.dart';
import 'biometric_auth.dart';
import 'device_key_store.dart';
import 'expense_api.dart';
import 'local_store.dart';
import 'server_config.dart';
import 'session_store.dart';

/// Connexion au serveur : son adresse et la session du compte. Sans session, l'app reste
/// pleinement utilisable sur l'appareil.
class AccountRepository extends ChangeNotifier {
  AccountRepository({
    required this._store,
    required this._sessions,
    required this._deviceKeys,
    required this._biometrics,
    required http.Client httpClient,
    String? defaultServerAddress,
  }) : _defaultServerAddress = defaultServerAddress ?? defaultServerUrl {
    _api = AuthApi(client: httpClient, settings: () => settings);
  }

  final LocalStore _store;
  final SessionStore _sessions;
  final DeviceKeyStore _deviceKeys;
  final BiometricAuth _biometrics;
  late final AuthApi _api;

  /// Adresse du build, utilisée quand aucune n'est saisie.
  final String _defaultServerAddress;
  var _serverAddressOverride = '';
  Session? _session;
  var _biometricAvailable = false;
  var _biometricEnabled = false;

  /// Adresse effective : celle saisie dans l'app, sinon celle du build.
  ServerSettings get settings => ServerSettings(
    baseUrl: _serverAddressOverride.isEmpty
        ? _defaultServerAddress
        : _serverAddressOverride,
  );

  /// Adresse saisie dans l'app (vide : celle du build).
  String get serverAddressOverride => _serverAddressOverride;

  Session? get session => _session;

  bool get signedIn => _session != null;

  /// L'appareil a une biométrie utilisable : la connexion par empreinte peut être proposée.
  bool get biometricAvailable => _biometricAvailable;

  /// Une clé d'appareil est enregistrée : la connexion par empreinte est activée.
  bool get biometricEnabled => _biometricEnabled;

  /// Synchronisation possible : un serveur et une session.
  bool get connected => settings.isConfigured && signedIn;

  Future<void> load() async {
    _serverAddressOverride = await _store.setting('baseUrl') ?? '';
    _session = await _sessions.read();
    _biometricAvailable = await _biometrics.isAvailable();
    _biometricEnabled = await _deviceKeys.exists();
    notifyListeners();
  }

  Future<void> saveServerAddress(String baseUrl) async {
    final trimmed = baseUrl.trim();
    await _store.setSetting('baseUrl', trimmed);
    _serverAddressOverride = trimmed;
    notifyListeners();
  }

  Future<void> register(String email, String password) async {
    await _open(() => _api.register(email.trim(), password));
    await _forgetDeviceKeyOfAnotherAccount();
  }

  Future<void> login(String email, String password) async {
    await _open(() => _api.login(email.trim(), password));
    await _forgetDeviceKeyOfAnotherAccount();
  }

  /// Efface la session de l'appareil, puis la révoque sur le serveur si possible.
  /// Les données locales sont conservées.
  Future<void> logout() async {
    final token = _session?.token;
    await expire();
    if (token == null || !settings.isConfigured) return;
    try {
      await _api.logout(token);
    } on Exception catch (e) {
      // Hors-ligne ou serveur en erreur : la session expirera d'elle-même côté serveur.
      debugPrint('Révocation de la session impossible : $e');
    }
  }

  /// Après une authentification biométrique, demande une clé d'appareil au serveur et la garde
  /// dans le stockage sécurisé.
  Future<void> enableBiometricLogin() async {
    final session = _session;
    if (session == null) return;
    if (!await _biometrics.authenticate('Activer la connexion par empreinte')) {
      return;
    }
    try {
      await _deviceKeys.write(
        await _api.registerDevice(session.token, Platform.operatingSystem),
        owner: session.account.email,
      );
    } on UnauthorizedException {
      return expire();
    }
    _biometricEnabled = true;
    notifyListeners();
  }

  /// Se connecte avec la clé d'appareil, lue seulement après une authentification biométrique
  /// réussie. Clé refusée par le serveur → effacée, [AuthException].
  Future<void> loginWithBiometrics() async {
    if (!await _biometrics.authenticate('Se connecter à votre compte')) return;
    final deviceKey = await _deviceKeys.read();
    if (deviceKey == null) return _forgetDeviceKey();
    try {
      await _open(() => _api.deviceLogin(deviceKey));
    } on UnauthorizedException {
      await _forgetDeviceKey();
      throw AuthException(
        'La connexion par empreinte n\'est plus valide : '
        'connectez-vous avec votre mot de passe.',
      );
    }
  }

  /// Efface la clé d'appareil, puis la révoque sur le serveur si possible.
  Future<void> disableBiometricLogin() async {
    final deviceKey = await _deviceKeys.read();
    await _forgetDeviceKey();
    final token = _session?.token;
    if (deviceKey == null || token == null || !settings.isConfigured) return;
    try {
      await _api.revokeDevice(token, deviceKey);
    } on Exception catch (e) {
      // Hors-ligne ou session expirée : la clé n'existe plus sur l'appareil.
      debugPrint('Révocation de la clé d\'appareil impossible : $e');
    }
  }

  /// La clé d'appareil reste liée au compte qui l'a activée : connecté à un autre compte
  /// (ou à un compte inconnu de la clé), elle est effacée sans être révoquée — seule une session
  /// de son compte le pourrait.
  Future<void> _forgetDeviceKeyOfAnotherAccount() async {
    if (!_biometricEnabled) return;
    if (await _deviceKeys.owner() == _session?.account.email) return;
    await _forgetDeviceKey();
  }

  Future<void> _forgetDeviceKey() async {
    await _deviceKeys.clear();
    _biometricEnabled = false;
    notifyListeners();
  }

  /// Relit le compte sur le serveur (offre, usage et quota à jour) ; une session refusée
  /// déconnecte, une autre erreur laisse le compte tel quel.
  Future<void> refresh() async {
    final current = _session;
    if (current == null || !settings.isConfigured) return;
    try {
      final account = await _api.account(current.token);
      await _keep(current.copyWith(account: account));
    } on UnauthorizedException {
      await expire();
    } on OfflineException catch (e) {
      debugPrint('Compte non rafraîchi (hors-ligne) : $e');
    } on ApiException catch (e) {
      debugPrint('Compte non rafraîchi : $e');
    }
  }

  /// Session refusée par le serveur : retour à l'état déconnecté.
  Future<void> expire() async {
    await _sessions.clear();
    _session = null;
    notifyListeners();
  }

  Future<void> _open(Future<Session> Function() authenticate) async {
    if (!settings.isConfigured) {
      throw AuthException(
        'Renseignez d\'abord l\'adresse du serveur (section « Avancé »).',
      );
    }
    await _keep(await authenticate());
    await refresh(); // usage et quota, absents de la réponse de connexion
  }

  Future<void> _keep(Session session) async {
    await _sessions.write(session);
    _session = session;
    notifyListeners();
  }
}

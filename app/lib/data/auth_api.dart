import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../domain/account.dart';
import 'expense_api.dart';

/// Refus d'une inscription ou d'une connexion, avec un message à afficher tel quel.
class AuthException implements Exception {
  AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Client de l'API `/api/auth` et `/api/account`.
final class AuthApi {
  AuthApi({required this._client, required this._settings});

  final http.Client _client;
  final ServerSettings Function() _settings;

  Future<Session> register(String email, String password) =>
      _authenticate('/api/auth/register', email, password);

  Future<Session> login(String email, String password) =>
      _authenticate('/api/auth/login', email, password);

  Future<void> logout(String token) async {
    final response = await _send(
      () => _client.post(_uri('/api/auth/logout'), headers: _bearer(token)),
    );
    if (response.statusCode == 401) return; // déjà expirée : rien à révoquer
    _check(response);
  }

  Future<Account> account(String token) async {
    final response = await _send(
      () => _client.get(_uri('/api/account'), headers: _bearer(token)),
    );
    if (response.statusCode == 401) throw UnauthorizedException();
    return Account.fromJson(_json(_check(response)));
  }

  Future<Session> _authenticate(
    String path,
    String email,
    String password,
  ) async {
    final response = await _send(
      () => _client.post(
        _uri(path),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      ),
    );
    final message = switch (response.statusCode) {
      400 =>
        'Adresse e-mail invalide ou mot de passe trop court '
            '(10 caractères minimum).',
      401 => 'E-mail ou mot de passe incorrect.',
      409 => 'Un compte existe déjà avec cette adresse e-mail.',
      _ => null,
    };
    if (message != null) throw AuthException(message);
    final json = _json(_check(response));
    return Session(
      token: json['token']! as String,
      account: Account.fromJson(json['account']! as Map<String, Object?>),
    );
  }

  Future<http.Response> _send(Future<http.Response> Function() call) async {
    try {
      return await call().timeout(const Duration(seconds: 30));
    } on SocketException catch (e) {
      throw OfflineException(e);
    } on http.ClientException catch (e) {
      throw OfflineException(e);
    } on HttpException catch (e) {
      throw OfflineException(e);
    }
  }

  static http.Response _check(http.Response response) {
    if (response.statusCode >= 300) {
      throw ApiException(response.statusCode, response.body);
    }
    return response;
  }

  static Map<String, Object?> _json(http.Response r) =>
      jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, Object?>;

  static Map<String, String> _bearer(String token) => {
    'Authorization': 'Bearer $token',
  };

  Uri _uri(String path) {
    final base = _settings().baseUrl.replaceFirst(RegExp(r'/+$'), '');
    return Uri.parse('$base$path');
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

final class ServerSettings {
  const ServerSettings({required this.baseUrl});

  final String baseUrl;

  bool get isConfigured => baseUrl.trim().isNotEmpty;
}

/// Le serveur est injoignable : l'opération sera rejouée plus tard.
class OfflineException implements Exception {
  OfflineException(this.cause);

  final Object cause;

  @override
  String toString() => 'Serveur injoignable ($cause)';
}

class ApiException implements Exception {
  ApiException(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  String toString() => 'Erreur serveur $statusCode : $body';
}

/// Envoi refusé : l'espace en ligne de l'offre serait dépassé. Rien n'a été stocké sur le serveur.
class QuotaExceededException extends ApiException {
  QuotaExceededException(
    super.statusCode,
    super.body, {
    required this.usedBytes,
    required this.quotaBytes,
  });

  final int usedBytes;
  final int quotaBytes;
}

/// La session est absente, expirée ou révoquée : l'utilisateur doit se reconnecter.
class UnauthorizedException implements Exception {
  @override
  String toString() => 'Session expirée';
}

/// Accès HTTP commun aux API du serveur : adresse, jeton de session et traduction des erreurs
/// (hors-ligne, session refusée, quota dépassé).
final class ServerClient {
  ServerClient({
    required this._client,
    required this._settings,
    required this._token,
  });

  final http.Client _client;
  final ServerSettings Function() _settings;

  /// Jeton de la session en cours (`null` : pas de session).
  final String? Function() _token;

  Future<http.Response> get(String path, [Map<String, String>? query]) =>
      send(() => _client.get(uri(path, query), headers: headers()));

  Future<http.Response> post(String path, [Map<String, String>? query]) =>
      send(() => _client.post(uri(path, query), headers: headers()));

  Future<http.Response> putJson(String path, Object? body) => send(
    () => _client.put(
      uri(path),
      headers: {...headers(), 'Content-Type': 'application/json'},
      body: jsonEncode(body),
    ),
  );

  /// Une ressource déjà absente compte comme supprimée.
  Future<void> delete(String path) async {
    await send(
      () => _client.delete(uri(path), headers: headers()),
      acceptNotFound: true,
    );
  }

  /// Envoi multipart : [build] reçoit une requête authentifiée vers [path] à compléter.
  Future<http.Response> multipart(
    String path,
    void Function(http.MultipartRequest request) build,
  ) {
    final request = http.MultipartRequest('POST', uri(path))
      ..headers.addAll(headers());
    build(request);
    return send(
      () async => http.Response.fromStream(await _client.send(request)),
    );
  }

  Future<http.Response> send(
    Future<http.Response> Function() call, {
    bool acceptNotFound = false,
  }) async {
    final http.Response response;
    try {
      response = await call().timeout(const Duration(seconds: 60));
    } on SocketException catch (e) {
      throw OfflineException(e);
    } on http.ClientException catch (e) {
      throw OfflineException(e);
    } on HttpException catch (e) {
      throw OfflineException(e);
    }
    if (response.statusCode == 401) throw UnauthorizedException();
    if (response.statusCode == 404 && acceptNotFound) return response;
    if (response.statusCode == 403) _throwIfQuotaExceeded(response);
    if (response.statusCode >= 300) {
      throw ApiException(response.statusCode, response.body);
    }
    return response;
  }

  static Object? json(http.Response r) => jsonDecode(utf8.decode(r.bodyBytes));

  Map<String, String> headers() {
    final token = _token();
    return token == null ? {} : {'Authorization': 'Bearer $token'};
  }

  Uri uri(String path, [Map<String, String>? query]) {
    final base = _settings().baseUrl.replaceFirst(RegExp(r'/+$'), '');
    return Uri.parse('$base$path').replace(queryParameters: query);
  }

  static http.MultipartFile file(
    String field,
    List<int> bytes,
    String contentType, {
    String? filename,
  }) {
    final parts = contentType.split('/');
    return http.MultipartFile.fromBytes(
      field,
      bytes,
      filename: filename ?? field,
      contentType: http.MediaType(
        parts.first,
        parts.length > 1 ? parts[1] : 'octet-stream',
      ),
    );
  }

  static void _throwIfQuotaExceeded(http.Response response) {
    final Object? body;
    try {
      body = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      return;
    }
    if (body is! Map<String, Object?> || body['code'] != 'QUOTA_EXCEEDED') {
      return;
    }
    // Corps inattendu : reste une ApiException ordinaire (levée par l'appelant).
    if (body['usedBytes'] case final int used) {
      if (body['quotaBytes'] case final int quota) {
        throw QuotaExceededException(
          response.statusCode,
          response.body,
          usedBytes: used,
          quotaBytes: quota,
        );
      }
    }
  }
}

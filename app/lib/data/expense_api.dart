import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../domain/expense.dart';
import '../domain/quad.dart';

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

/// Client de l'API REST `/api/expenses`.
final class ExpenseApi {
  ExpenseApi({
    required this._client,
    required this._settings,
    required this._token,
  });

  final http.Client _client;
  final ServerSettings Function() _settings;

  /// Jeton de la session en cours (`null` : pas de session).
  final String? Function() _token;

  Future<Expense> upload(
    Expense e,
    List<int> original,
    String contentType,
  ) async {
    final request = http.MultipartRequest('POST', _uri('/api/expenses'))
      ..headers.addAll(_headers())
      ..fields['id'] = e.id
      ..fields['filter'] = e.filter.code
      ..fields.addAll({if (e.corners != null) 'corners': e.corners!.format()})
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          original,
          filename: 'original',
          contentType: _mediaType(contentType),
        ),
      );
    final response = await _send(
      () async => http.Response.fromStream(await _client.send(request)),
    );
    return Expense.fromServerJson(_json(response) as Map<String, Object?>);
  }

  Future<Expense> update(Expense e) async {
    final response = await _send(
      () => _client.put(
        _uri('/api/expenses/${e.id}'),
        headers: {..._headers(), 'Content-Type': 'application/json'},
        body: jsonEncode(e.toUpdateJson()),
      ),
    );
    return Expense.fromServerJson(_json(response) as Map<String, Object?>);
  }

  Future<Expense> reprocess(
    String id,
    ImageFilter filter,
    Quad? corners,
  ) async {
    final response = await _send(
      () => _client.post(
        _uri('/api/expenses/$id/reprocess', {
          'filter': filter.code,
          if (corners != null) 'corners': corners.format(),
        }),
        headers: _headers(),
      ),
    );
    return Expense.fromServerJson(_json(response) as Map<String, Object?>);
  }

  /// Supprime côté serveur ; une dépense déjà absente est considérée comme supprimée.
  Future<void> delete(String id) async {
    await _send(
      () => _client.delete(_uri('/api/expenses/$id'), headers: _headers()),
      acceptNotFound: true,
    );
  }

  Future<List<Expense>> changesSince(DateTime? since) async {
    final from = since ?? DateTime.utc(1970);
    final response = await _send(
      () => _client.get(
        _uri('/api/expenses/changes', {
          'since': from.toUtc().toIso8601String(),
        }),
        headers: _headers(),
      ),
    );
    return (_json(response) as List)
        .cast<Map<String, Object?>>()
        .map(Expense.fromServerJson)
        .toList();
  }

  Future<List<int>> processedImage(String id) =>
      _bytes('/api/expenses/$id/processed');

  Future<({List<int> bytes, String contentType})> originalImage(
    String id,
  ) async {
    final response = await _send(
      () =>
          _client.get(_uri('/api/expenses/$id/original'), headers: _headers()),
    );
    return (
      bytes: response.bodyBytes,
      contentType: response.headers['content-type'] ?? 'image/jpeg',
    );
  }

  Future<List<int>> _bytes(String path) async =>
      (await _send(() => _client.get(_uri(path), headers: _headers())))
          .bodyBytes;

  Future<http.Response> _send(
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

  Object? _json(http.Response r) => jsonDecode(utf8.decode(r.bodyBytes));

  Map<String, String> _headers() {
    final token = _token();
    return token == null ? {} : {'Authorization': 'Bearer $token'};
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = _settings().baseUrl.replaceFirst(RegExp(r'/+$'), '');
    return Uri.parse('$base$path').replace(queryParameters: query);
  }

  static http.MediaType _mediaType(String contentType) {
    final parts = contentType.split('/');
    return http.MediaType(
      parts.first,
      parts.length > 1 ? parts[1] : 'octet-stream',
    );
  }
}

/// La session est absente, expirée ou révoquée : l'utilisateur doit se reconnecter.
class UnauthorizedException implements Exception {
  @override
  String toString() => 'Session expirée';
}

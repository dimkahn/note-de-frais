import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Faux serveur : mémorise les requêtes et répond selon les routes de l'API.
class FakeServer {
  final requests = <http.Request>[];

  /// Valeur d'un champ multipart du dernier envoi.
  String? uploadedField(String name) {
    final upload = requests.lastWhere(
      (r) => r.method == 'POST' && r.url.path == '/api/expenses',
    );
    final body = utf8.decode(upload.bodyBytes, allowMalformed: true);
    return RegExp('name="$name"\r\n\r\n([^\r]+)').firstMatch(body)?.group(1);
  }

  final expenses = <String, Map<String, Object?>>{};
  bool offline = false;

  /// Comptes connus (e-mail → mot de passe) et jetons de session valides.
  final accounts = <String, String>{};
  final sessions = <String>{'jeton'};
  final premium = <String>{};

  /// Usage rapporté par `GET /api/account` ; espace plein → envois refusés (403 QUOTA_EXCEEDED).
  var usedBytes = 0;
  var quotaBytes = 100 * 1024 * 1024;
  var quotaFull = false;

  /// `GET /api/account` en erreur 500.
  var accountFails = false;

  /// Clés d'appareil valides (clé → e-mail du compte).
  final deviceKeys = <String, String>{};
  var _issued = 0;

  /// Révoque toutes les sessions (expiration côté serveur).
  void expireSessions() => sessions.clear();

  late final client = MockClient((request) async {
    if (offline) throw const SocketException('hors ligne');
    requests.add(request);
    final path = request.url.path;
    if (path == '/api/auth/register' || path == '/api/auth/login') {
      return _authenticate(request);
    }
    if (path == '/api/auth/device-login') return _deviceLogin(request);
    final token = request.headers['Authorization']?.replaceFirst('Bearer ', '');
    if (!sessions.contains(token)) return http.Response('', 401);
    if (path == '/api/auth/logout') {
      sessions.remove(token);
      return http.Response('', 204);
    }
    if (path == '/api/account') {
      if (accountFails) return http.Response('boom', 500);
      final email = _emailOf(token!);
      return _ok({
        ..._account(email),
        'usedBytes': usedBytes,
        'quotaBytes': quotaBytes,
        'aiAnalysis': premium.contains(email),
      });
    }
    if (path == '/api/auth/devices') {
      final deviceKey = 'cle-${++_issued}';
      deviceKeys[deviceKey] = _emailOf(token!);
      return _ok({'deviceKey': deviceKey}, 201);
    }
    if (path == '/api/auth/devices/current') {
      deviceKeys.remove(_body(request)['deviceKey']);
      return http.Response('', 204);
    }

    final id = path.split('/').length > 3 ? path.split('/')[3] : null;

    if (request.method == 'POST' && path == '/api/expenses') {
      if (quotaFull) {
        return _ok({
          'status': 403,
          'code': 'QUOTA_EXCEEDED',
          'usedBytes': quotaBytes,
          'quotaBytes': quotaBytes,
        }, 403);
      }
      final body = utf8.decode(request.bodyBytes, allowMalformed: true);
      final uploadedId = RegExp(r'name="id"\r\n\r\n([^\r]+)')
          .firstMatch(body)!
          .group(1)!;
      expenses[uploadedId] = _json(uploadedId, status: 'PENDING');
      return _ok(expenses[uploadedId], 202);
    }
    if (request.method == 'PUT') {
      final update = jsonDecode(request.body) as Map<String, Object?>;
      expenses[id!] = {
        ...expenses[id] ?? _json(id),
        ...update,
        'userEdited': true,
      };
      return _ok(expenses[id]);
    }
    if (request.method == 'DELETE') {
      expenses.remove(id);
      return http.Response('', 204);
    }
    if (path.endsWith('/reprocess')) return _ok(expenses[id], 202);
    if (path == '/api/expenses/changes') return _ok(expenses.values.toList());
    if (path.endsWith('/processed')) return http.Response.bytes([7, 7], 200);
    if (path.endsWith('/original')) return http.Response.bytes([1, 1], 200);
    return http.Response('introuvable', 404);
  });

  final _owners = <String, String>{};

  http.Response _authenticate(http.Request request) {
    final body = _body(request);
    final email = body['email']! as String;
    final password = body['password']! as String;
    if (request.url.path.endsWith('/register')) {
      if (accounts.containsKey(email)) return http.Response('', 409);
      accounts[email] = password;
    } else if (accounts[email] != password) {
      return http.Response('', 401);
    }
    return _openSession(email);
  }

  http.Response _deviceLogin(http.Request request) {
    final email = deviceKeys[_body(request)['deviceKey']];
    if (email == null) return http.Response('', 401);
    return _openSession(email);
  }

  http.Response _openSession(String email) {
    final token = 'jeton-${++_issued}';
    sessions.add(token);
    _owners[token] = email;
    return _ok({'token': token, 'account': _account(email)});
  }

  static Map<String, Object?> _body(http.Request request) =>
      jsonDecode(request.body) as Map<String, Object?>;

  String _emailOf(String token) => _owners[token] ?? 'alice@example.com';

  Map<String, Object?> _account(String email) => {
    'email': email,
    'plan': premium.contains(email) ? 'PREMIUM' : 'FREE',
  };

  static Map<String, Object?> _json(
    String id, {
    String status = 'DONE',
    bool processed = false,
  }) => {
    'id': id,
    'merchant': null,
    'status': status,
    'filter': 'ENHANCE',
    'hasProcessedImage': processed,
    'userEdited': false,
    'deleted': false,
    'createdAt': '2026-03-10T12:00:00Z',
    'updatedAt': '2026-03-10T12:00:00Z',
  };

  void processed(String id, {String merchant = 'Le Bistrot'}) {
    expenses[id] = {
      ..._json(id, processed: true),
      'merchant': merchant,
      'amountTotal': 42.5,
      'currency': 'EUR',
      'updatedAt': '2026-03-10T12:05:00Z',
    };
  }

  /// Rendu produit sans analyse IA (offre Gratuite).
  void processedWithoutAnalysis(String id) {
    expenses[id] = {
      ..._json(id, status: 'NOT_INCLUDED', processed: true),
      'updatedAt': '2026-03-10T12:05:00Z',
    };
  }

  static http.Response _ok(Object? body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

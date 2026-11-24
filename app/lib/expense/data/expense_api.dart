import 'package:http/http.dart' as http;

import '../domain/expense.dart';
import '../../scan/domain/quad.dart';
import '../../shared/data/server_client.dart';

export '../../shared/data/server_client.dart'
    show
        ApiException,
        OfflineException,
        QuotaExceededException,
        ServerSettings,
        UnauthorizedException;

/// Client de l'API REST `/api/expenses`.
final class ExpenseApi {
  ExpenseApi({
    required http.Client client,
    required ServerSettings Function() settings,
    required String? Function() token,
  }) : _server = ServerClient(client: client, settings: settings, token: token);

  final ServerClient _server;

  Future<Expense> upload(
    Expense e,
    List<int> original,
    String contentType,
  ) async {
    final response = await _server.multipart(
      '/api/expenses',
      (request) => request
        ..fields['id'] = e.id
        ..fields['filter'] = e.filter.code
        ..fields.addAll({if (e.corners != null) 'corners': e.corners!.format()})
        ..files.add(
          ServerClient.file(
            'file',
            original,
            contentType,
            filename: 'original',
          ),
        ),
    );
    return _expense(response);
  }

  Future<Expense> update(Expense e) async => _expense(
    await _server.putJson('/api/expenses/${e.id}', e.toUpdateJson()),
  );

  Future<Expense> reprocess(
    String id,
    ImageFilter filter,
    Quad? corners,
  ) async {
    final response = await _server.post('/api/expenses/$id/reprocess', {
      'filter': filter.code,
      if (corners != null) 'corners': corners.format(),
    });
    return _expense(response);
  }

  /// Supprime côté serveur ; une dépense déjà absente est considérée comme supprimée.
  Future<void> delete(String id) => _server.delete('/api/expenses/$id');

  Future<List<Expense>> changesSince(DateTime? since) async {
    final from = since ?? DateTime.utc(1970);
    final response = await _server.get('/api/expenses/changes', {
      'since': from.toUtc().toIso8601String(),
    });
    return (ServerClient.json(response) as List)
        .cast<Map<String, Object?>>()
        .map(Expense.fromServerJson)
        .toList();
  }

  Future<List<int>> processedImage(String id) async =>
      (await _server.get('/api/expenses/$id/processed')).bodyBytes;

  Future<({List<int> bytes, String contentType})> originalImage(
    String id,
  ) async {
    final response = await _server.get('/api/expenses/$id/original');
    return (
      bytes: response.bodyBytes,
      contentType: response.headers['content-type'] ?? 'image/jpeg',
    );
  }

  static Expense _expense(http.Response response) => Expense.fromServerJson(
    ServerClient.json(response) as Map<String, Object?>,
  );
}

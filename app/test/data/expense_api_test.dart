import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:note_de_frais/data/expense_api.dart';
import 'package:note_de_frais/domain/expense.dart';

ExpenseApi _api(
  MockClientHandler handler, {
  String baseUrl = 'http://serveur:8080/',
  String? token,
}) => ExpenseApi(
  client: MockClient(handler),
  settings: () => ServerSettings(baseUrl: baseUrl),
  token: () => token,
);

void main() {
  test(
    'construit les URL sans double barre et sans jeton hors session',
    () async {
      late http.Request seen;
      final api = _api((r) async {
        seen = r;
        return http.Response('[]', 200);
      });

      await api.changesSince(DateTime.utc(2026, 3, 10));

      expect(
        seen.url.toString(),
        'http://serveur:8080/api/expenses/changes?since=2026-03-10T00%3A00%3A00.000Z',
      );
      expect(seen.headers.containsKey('Authorization'), isFalse);
    },
  );

  test('présente le jeton de session en Authorization Bearer', () async {
    late http.Request seen;
    final api = _api((r) async {
      seen = r;
      return http.Response('[]', 200);
    }, token: 'jeton');

    await api.changesSince(null);

    expect(seen.headers['Authorization'], 'Bearer jeton');
  });

  test('une session refusée devient une UnauthorizedException', () async {
    final api = _api((_) async => http.Response('', 401), token: 'perime');

    expect(api.changesSince(null), throwsA(isA<UnauthorizedException>()));
  });

  test('une erreur HTTP devient une ApiException avec le code', () async {
    final api = _api((_) async => http.Response('boom', 500));

    expect(
      api.changesSince(null),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'code', 500)),
    );
  });

  test('une erreur réseau devient une OfflineException', () async {
    final api = _api((_) async => throw const SocketException('pas de réseau'));

    expect(api.changesSince(null), throwsA(isA<OfflineException>()));
  });

  test(
    'supprimer une dépense déjà absente du serveur n\'est pas une erreur',
    () async {
      final api = _api((_) async => http.Response('', 404));

      await expectLater(api.delete('abc'), completes);
    },
  );

  test('un envoi refusé pour quota devient une QuotaExceededException avec l\'usage et le quota', () async {
    final api = _api(
      (_) async => http.Response(
        '{"status":403,"code":"QUOTA_EXCEEDED","usedBytes":104000000,"quotaBytes":104857600}',
        403,
        headers: {'content-type': 'application/problem+json'},
      ),
    );

    expect(
      api.upload(const Expense(id: 'a'), [1, 2, 3], 'image/jpeg'),
      throwsA(
        isA<QuotaExceededException>()
            .having((e) => e.usedBytes, 'usedBytes', 104000000)
            .having((e) => e.quotaBytes, 'quotaBytes', 104857600),
      ),
    );
  });

  test('un autre refus 403 reste une ApiException ordinaire', () async {
    final api = _api((_) async => http.Response('{"status":403}', 403));

    expect(
      api.upload(const Expense(id: 'a'), [1], 'image/jpeg'),
      throwsA(isNot(isA<QuotaExceededException>())),
    );
  });

  test(
    'un refus pour quota sans usage lisible reste une ApiException ordinaire',
    () async {
      final api = _api(
        (_) async => http.Response('{"code":"QUOTA_EXCEEDED"}', 403),
      );

      expect(
        api.upload(const Expense(id: 'a'), [1], 'image/jpeg'),
        throwsA(
          isA<ApiException>().having(
            (e) => e is QuotaExceededException,
            'quota',
            isFalse,
          ),
        ),
      );
    },
  );
}

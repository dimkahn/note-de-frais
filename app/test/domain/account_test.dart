import 'package:flutter_test/flutter_test.dart';
import 'package:note_de_frais/domain/account.dart';

void main() {
  test('lit un compte renvoyé par le serveur', () {
    final account = Account.fromJson({
      'email': 'alice@example.com',
      'plan': 'PREMIUM',
    });

    expect(
      account,
      const Account(email: 'alice@example.com', plan: Plan.premium),
    );
  });

  test('une offre inconnue est traitée comme l\'offre gratuite', () {
    final account = Account.fromJson({'email': 'a@b.fr', 'plan': 'GOLD'});

    expect(account.plan, Plan.free);
  });

  test('un compte relu après enregistrement est identique', () {
    const account = Account(email: 'alice@example.com', plan: Plan.free);

    final reread = Account.fromJson(account.toJson());

    expect(reread, account);
  });

  test('lit l\'usage, le quota et l\'analyse IA de la page Compte', () {
    final account = Account.fromJson({
      'email': 'alice@example.com',
      'plan': 'FREE',
      'usedBytes': 44040192,
      'quotaBytes': 104857600,
      'aiAnalysis': false,
    });

    expect(
      account.usage,
      const StorageUsage(usedBytes: 44040192, quotaBytes: 104857600),
    );
    expect(account.aiAnalysis, isFalse);
  });

  test(
    'sans usage dans la réponse (inscription, connexion), l\'usage est inconnu',
    () {
      final account = Account.fromJson({'email': 'a@b.fr', 'plan': 'PREMIUM'});

      expect(account.usage, isNull);
      expect(account.aiAnalysis, isTrue);
    },
  );

  test('un compte avec son usage relu après enregistrement est identique', () {
    const account = Account(
      email: 'alice@example.com',
      plan: Plan.free,
      usage: StorageUsage(usedBytes: 10, quotaBytes: 100),
      aiAnalysis: false,
    );

    final reread = Account.fromJson(account.toJson());

    expect(reread, account);
  });

  group('usage de l\'espace en ligne', () {
    test('donne la part utilisée', () {
      const usage = StorageUsage(usedBytes: 42, quotaBytes: 100);

      expect(usage.fraction, 0.42);
    });

    test('la part utilisée est bornée à 1 au-delà du quota', () {
      const usage = StorageUsage(usedBytes: 120, quotaBytes: 100);

      expect(usage.fraction, 1);
    });

    test('est presque plein au-delà de 90 %', () {
      expect(
        const StorageUsage(usedBytes: 91, quotaBytes: 100).nearlyFull,
        isTrue,
      );
      expect(
        const StorageUsage(usedBytes: 90, quotaBytes: 100).nearlyFull,
        isFalse,
      );
    });
  });
}

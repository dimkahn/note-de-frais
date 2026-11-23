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
}

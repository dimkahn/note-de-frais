import 'package:flutter_test/flutter_test.dart';
import 'package:note_de_frais/ui/format.dart';

void main() {
  test('formate un montant à la française sans passer par un double', () {
    expect(formatAmount('1234.50', 'EUR'), '1 234,50 €');
    expect(formatAmount('0.10', 'CHF'), '0,10 CHF');
    expect(formatAmount(null, 'EUR'), '—');
  });

  test('affiche les totaux de plusieurs devises', () {
    expect(
      formatTotals({'CHF': '30.00', 'EUR': '35.50'}),
      '30,00 CHF · 35,50 €',
    );
    expect(formatTotals({}), '—');
  });
}

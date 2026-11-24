import 'package:flutter_test/flutter_test.dart';
import 'package:note_de_frais/shared/ui/format.dart';

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

  test('formate une place de stockage en Mo, puis en Go au-delà de 1 Go', () {
    const mo = 1024 * 1024;
    expect(formatStorage(42 * mo), '42 Mo');
    expect(formatStorage(100 * mo), '100 Mo');
    expect(formatStorage(0), '0 Mo');
    expect(formatStorage(300 * 1024), '0,3 Mo');
    expect(formatStorage(1024 * mo), '1 Go');
    expect(formatStorage(1536 * mo), '1,5 Go');
  });
}

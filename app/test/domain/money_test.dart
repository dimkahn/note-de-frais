import 'package:flutter_test/flutter_test.dart';
import 'package:note_de_frais/domain/money.dart';

void main() {
  group('normalizeAmount', () {
    test('formate un nombre JSON à deux décimales', () {
      expect(normalizeAmount(42.5), '42.50');
      expect(normalizeAmount(7), '7.00');
    });

    test('accepte la virgule et les symboles saisis par l\'utilisateur', () {
      expect(normalizeAmount('12,3 €'), '12.30');
    });

    test('renvoie null pour une saisie vide ou illisible', () {
      expect(normalizeAmount(''), isNull);
      expect(normalizeAmount('abc'), isNull);
      expect(normalizeAmount('1.234'), isNull);
      expect(normalizeAmount(null), isNull);
    });
  });

  group('centimes', () {
    test('aller-retour exact', () {
      expect(parseCents('35.5'), 3550);
      expect(formatCents(3550), '35.50');
      expect(formatCents(-5), '-0.05');
    });

    test('0.1 + 0.2 vaut exactement 0.30', () {
      expect(formatCents(parseCents('0.1')! + parseCents('0.2')!), '0.30');
    });
  });
}

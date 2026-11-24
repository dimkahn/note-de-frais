import 'package:flutter_test/flutter_test.dart';
import 'package:note_de_frais/expense/domain/category_breakdown.dart';
import 'package:note_de_frais/expense/domain/expense.dart';

Expense _e(
  String id,
  ExpenseCategory? category,
  String? amount, {
  String currency = 'EUR',
}) => Expense.draft(
  id: id,
  originalPath: '/o',
  filter: ImageFilter.enhance,
).copyWith(category: category, amountTotal: amount, currency: currency);

void main() {
  test('répartit le total par type, du plus gros au plus petit', () {
    final expenses = [
      _e('a', ExpenseCategory.restaurant, '20.00'),
      _e('b', ExpenseCategory.hotel, '90.00'),
      _e('c', ExpenseCategory.restaurant, '10.00'),
    ];

    final shares = categoryBreakdown(expenses)!;

    expect(shares.map((s) => s.category), [
      ExpenseCategory.hotel,
      ExpenseCategory.restaurant,
    ]);
    expect(shares.map((s) => s.amount), ['90.00', '30.00']);
    expect(shares.map((s) => s.fraction), [0.75, 0.25]);
  });

  test('regroupe les dépenses sans type sous une part sans catégorie', () {
    final expenses = [
      _e('a', null, '5.00'),
      _e('b', ExpenseCategory.taxi, '15.00'),
    ];

    final shares = categoryBreakdown(expenses)!;

    expect(shares.last.category, isNull);
    expect(shares.last.amount, '5.00');
  });

  test('ignore les dépenses sans montant', () {
    final expenses = [
      _e('a', ExpenseCategory.parking, null),
      _e('b', ExpenseCategory.taxi, '15.00'),
    ];

    final shares = categoryBreakdown(expenses)!;

    expect(shares.single.category, ExpenseCategory.taxi);
    expect(shares.single.fraction, 1.0);
  });

  test('ne répartit pas plusieurs devises entre elles', () {
    final expenses = [
      _e('a', ExpenseCategory.hotel, '90.00'),
      _e('b', ExpenseCategory.restaurant, '10.00', currency: 'USD'),
    ];

    expect(categoryBreakdown(expenses), isNull);
  });

  test('ne répartit rien sans montant', () {
    expect(categoryBreakdown([_e('a', ExpenseCategory.hotel, null)]), isNull);
    expect(categoryBreakdown(const []), isNull);
  });

  test('ignore les montants négatifs (remboursements) dans la répartition', () {
    final expenses = [
      _e('a', ExpenseCategory.hotel, '90.00'),
      _e('b', ExpenseCategory.train, '-30.00'),
    ];

    final shares = categoryBreakdown(expenses)!;

    expect(shares.single.category, ExpenseCategory.hotel);
    expect(shares.single.fraction, 1.0);
  });
}

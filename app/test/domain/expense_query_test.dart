import 'package:flutter_test/flutter_test.dart';
import 'package:note_de_frais/domain/expense.dart';
import 'package:note_de_frais/domain/expense_query.dart';

Expense _e(
  String merchant,
  ExpenseCategory category,
  String city,
  DateTime date,
  String amount, {
  String currency = 'EUR',
  bool deleted = false,
}) =>
    Expense.draft(
      id: merchant,
      originalPath: '/o',
      filter: ImageFilter.enhance,
    ).copyWith(
      merchant: merchant,
      category: category,
      city: city,
      expenseDate: date,
      amountTotal: amount,
      currency: currency,
      deleted: deleted,
    );

void main() {
  final expenses = [
    _e(
      'Le Bistrot',
      ExpenseCategory.restaurant,
      'Paris',
      DateTime(2026, 3, 10),
      '20.00',
    ),
    _e(
      'Brasserie',
      ExpenseCategory.restaurant,
      'Lyon',
      DateTime(2026, 3, 15),
      '15.50',
    ),
    _e(
      'Café Genève',
      ExpenseCategory.restaurant,
      'Genève',
      DateTime(2026, 4, 2),
      '30.00',
      currency: 'CHF',
    ),
    _e('Ibis', ExpenseCategory.hotel, 'Lyon', DateTime(2026, 3, 15), '90.00'),
    _e(
      'Supprimée',
      ExpenseCategory.hotel,
      'Lyon',
      DateTime(2026, 3, 15),
      '1.00',
      deleted: true,
    ),
  ];

  group('ExpenseQuery', () {
    test('filtre par catégorie et ignore les supprimées', () {
      final r = const ExpenseQuery(category: ExpenseCategory.hotel)
          .apply(expenses);

      expect(r.map((e) => e.merchant), ['Ibis']);
    });

    test('filtre par ville sans tenir compte de la casse', () {
      final r = const ExpenseQuery(city: 'lyon').apply(expenses);

      expect(r.map((e) => e.merchant), unorderedEquals(['Brasserie', 'Ibis']));
    });

    test('filtre par période bornes incluses', () {
      final r = ExpenseQuery(
        from: DateTime(2026, 3, 15),
        to: DateTime(2026, 4, 2),
      ).apply(expenses);

      expect(r.length, 3);
    });

    test('recherche libre sur commerçant et ville', () {
      final r = const ExpenseQuery(text: 'genè').apply(expenses);

      expect(r.single.merchant, 'Café Genève');
    });

    test('trie de la plus récente à la plus ancienne', () {
      final r = const ExpenseQuery().apply(expenses);

      expect(r.first.merchant, 'Café Genève');
    });
  });

  group('regroupement', () {
    test('par catégorie avec un total par devise', () {
      final groups = groupExpenses(
        const ExpenseQuery().apply(expenses),
        GroupBy.category,
      );

      final resto = groups.first;
      expect(resto.label, 'Restaurant');
      expect(resto.count, 3);
      expect(resto.totals, {'CHF': '30.00', 'EUR': '35.50'});
    });

    test('par mois du plus récent au plus ancien', () {
      final groups = groupExpenses(
        const ExpenseQuery().apply(expenses),
        GroupBy.month,
      );

      expect(groups.map((g) => g.key), ['2026-04', '2026-03']);
    });

    test('les valeurs absentes sont regroupées sous « Non renseigné »', () {
      final e = Expense.draft(
        id: 'x',
        originalPath: '/o',
        filter: ImageFilter.none,
      );

      final groups = groupExpenses([e], GroupBy.city);

      expect(groups.single.label, 'Non renseigné');
    });
  });
}

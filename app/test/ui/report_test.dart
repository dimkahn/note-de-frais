import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:note_de_frais/domain/expense.dart';
import 'package:note_de_frais/ui/report.dart';

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  Expense expense(String id, DateTime date, String amount, {String? vat}) =>
      Expense(
        id: id,
        merchant: 'Commerce $id',
        category: ExpenseCategory.restaurant,
        expenseDate: date,
        amountTotal: amount,
        amountVat: vat,
        currency: 'EUR',
        processedPath: '/img/$id.jpg',
        status: ProcessingStatus.done,
      );

  test('titre au nom du mois quand tout tient dans un mois', () {
    final report = reportOf([
      expense('a', DateTime(2026, 3, 10), '20.00'),
      expense('b', DateTime(2026, 3, 2), '5.50'),
    ]);

    expect(report.title, 'Note de frais — mars 2026');
  });

  test('titre avec la période sinon', () {
    final report = reportOf([
      expense('a', DateTime(2026, 3, 10), '20.00'),
      expense('b', DateTime(2026, 4, 2), '5.50'),
    ]);

    expect(report.title, 'Note de frais du 10 mars 2026 au 2 avr. 2026');
  });

  test('lignes dans l\'ordre chronologique, montants formatés', () {
    final report = reportOf([
      expense('a', DateTime(2026, 3, 10), '20.00', vat: '1.82'),
      expense('b', DateTime(2026, 3, 2), '5.50'),
    ]);

    expect(report.lines.map((l) => l.merchant), ['Commerce b', 'Commerce a']);
    expect(report.lines.last.total, '20,00 €');
    expect(report.lines.last.vat, '1,82 €');
    expect(report.lines.first.vat, '—');
    expect(report.lines.first.imagePath, '/img/b.jpg');
    expect(report.lines.first.caption, '2 mars 2026 · Commerce b · 5,50 €');
    expect(report.totals, '25,50 €');
  });
}

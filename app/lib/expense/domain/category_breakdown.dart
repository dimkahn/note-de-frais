import 'expense.dart';
import 'money.dart';

/// Part d'un type de dépense dans le total.
final class CategoryShare {
  const CategoryShare(this.category, this.amount, this.fraction);

  /// `null` : dépenses sans type.
  final ExpenseCategory? category;

  /// Montant décimal, ex. "30.00".
  final String amount;

  /// Part du total, entre 0 et 1 (pour l'affichage seulement).
  final double fraction;
}

/// Répartition du total par type, du plus gros au plus petit. `null` s'il n'y a aucun montant,
/// ou plusieurs devises : on n'additionne jamais des devises différentes.
List<CategoryShare>? categoryBreakdown(List<Expense> expenses) {
  final cents = <ExpenseCategory?, int>{};
  final currencies = <String?>{};
  for (final e in expenses) {
    final amount = e.amountTotal == null ? null : parseCents(e.amountTotal!);
    if (amount == null) continue;
    currencies.add(e.currency);
    cents.update(e.category, (c) => c + amount, ifAbsent: () => amount);
  }
  if (currencies.length != 1) return null;
  final total = cents.values.fold(0, (a, b) => a + b);
  if (total <= 0) return null;
  final entries = cents.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return [
    for (final entry in entries)
      CategoryShare(entry.key, formatCents(entry.value), entry.value / total),
  ];
}

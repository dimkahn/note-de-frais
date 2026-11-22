import 'expense.dart';
import 'money.dart';

/// Critères de filtre appliqués localement (fonctionne hors-ligne).
final class ExpenseQuery {
  const ExpenseQuery({this.category, this.city, this.from, this.to, this.text});

  final ExpenseCategory? category;
  final String? city;
  final DateTime? from;
  final DateTime? to;
  final String? text;

  bool get isEmpty =>
      category == null &&
      _blank(city) &&
      from == null &&
      to == null &&
      _blank(text);

  /// Dépenses non supprimées correspondant aux critères, de la plus récente à la plus ancienne.
  List<Expense> apply(Iterable<Expense> expenses) {
    final result = expenses.where((e) => !e.deleted && _matches(e)).toList()
      ..sort((a, b) {
        final da = a.effectiveDate, db = b.effectiveDate;
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return db.compareTo(da);
      });
    return result;
  }

  bool _matches(Expense e) {
    if (category != null && e.category != category) return false;
    if (!_blank(city) &&
        (e.city ?? '').toLowerCase() != city!.trim().toLowerCase()) {
      return false;
    }
    final date = e.effectiveDate;
    if (from != null && (date == null || date.isBefore(_day(from!)))) {
      return false;
    }
    if (to != null &&
        (date == null ||
            date.isAfter(_day(to!).add(const Duration(days: 1))))) {
      return false;
    }
    if (!_blank(text)) {
      final q = text!.trim().toLowerCase();
      final haystack = [
        e.merchant,
        e.city,
        e.description,
        e.address,
      ].whereType<String>().join(' ').toLowerCase();
      if (!haystack.contains(q)) return false;
    }
    return true;
  }

  ExpenseQuery copyWith({
    ExpenseCategory? category,
    String? city,
    DateTime? from,
    DateTime? to,
    String? text,
    bool clearCategory = false,
    bool clearCity = false,
    bool clearPeriod = false,
  }) => ExpenseQuery(
    category: clearCategory ? null : category ?? this.category,
    city: clearCity ? null : city ?? this.city,
    from: clearPeriod ? null : from ?? this.from,
    to: clearPeriod ? null : to ?? this.to,
    text: text ?? this.text,
  );

  static bool _blank(String? s) => s == null || s.trim().isEmpty;

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
}

/// Critères de regroupement proposés dans l'application.
enum GroupBy {
  none('Aucun'),
  category('Type'),
  month('Mois'),
  city('Lieu'),
  merchant('Commerçant'),
  paymentMethod('Paiement');

  const GroupBy(this.label);

  final String label;
}

final class ExpenseGroup {
  const ExpenseGroup({
    required this.key,
    required this.label,
    required this.expenses,
    required this.totals,
  });

  final String key;
  final String label;
  final List<Expense> expenses;

  /// Total par devise, ex. {'EUR': '35.50'} (aucune conversion implicite).
  final Map<String, String> totals;

  int get count => expenses.length;
}

const _unknownLabel = 'Non renseigné';
const _months = [
  'janvier', 'février', 'mars', 'avril', 'mai', 'juin', //
  'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
];

/// Regroupe des dépenses déjà filtrées/triées. Ordre : chronologique inverse pour les mois,
/// sinon par nombre de dépenses décroissant.
List<ExpenseGroup> groupExpenses(List<Expense> expenses, GroupBy by) {
  final buckets = <String, List<Expense>>{};
  for (final e in expenses) {
    buckets.putIfAbsent(_keyOf(e, by) ?? '', () => []).add(e);
  }
  final groups = [
    for (final entry in buckets.entries)
      ExpenseGroup(
        key: entry.key,
        label: _labelOf(entry.key, by),
        expenses: entry.value,
        totals: totalsByCurrency(entry.value),
      ),
  ];
  if (by == GroupBy.month) {
    groups.sort((a, b) => b.key.compareTo(a.key));
  } else {
    groups.sort((a, b) {
      final byCount = b.count.compareTo(a.count);
      return byCount != 0 ? byCount : a.label.compareTo(b.label);
    });
  }
  return groups;
}

Map<String, String> totalsByCurrency(Iterable<Expense> expenses) {
  final cents = <String, int>{};
  for (final e in expenses) {
    final amount = e.amountTotal == null ? null : parseCents(e.amountTotal!);
    if (amount == null) continue;
    final currency = e.currency ?? '?';
    cents[currency] = (cents[currency] ?? 0) + amount;
  }
  final sortedKeys = cents.keys.toList()..sort();
  return {for (final k in sortedKeys) k: formatCents(cents[k]!)};
}

String? _keyOf(Expense e, GroupBy by) => switch (by) {
  GroupBy.none => 'all',
  GroupBy.category => e.category?.code,
  GroupBy.city => _nonBlank(e.city),
  GroupBy.merchant => _nonBlank(e.merchant),
  GroupBy.paymentMethod => _nonBlank(e.paymentMethod),
  GroupBy.month =>
    e.effectiveDate == null
        ? null
        : '${e.effectiveDate!.year}-${e.effectiveDate!.month.toString().padLeft(2, '0')}',
};

String _labelOf(String key, GroupBy by) {
  if (key.isEmpty) return _unknownLabel;
  return switch (by) {
    GroupBy.none => 'Toutes les dépenses',
    GroupBy.category => ExpenseCategory.fromCode(key)!.label,
    GroupBy.month =>
      '${_months[int.parse(key.substring(5)) - 1]} ${key.substring(0, 4)}',
    _ => key,
  };
}

String? _nonBlank(String? s) => s == null || s.trim().isEmpty ? null : s.trim();

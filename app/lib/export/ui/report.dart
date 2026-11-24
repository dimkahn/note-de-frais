import 'package:intl/intl.dart';

import '../data/export_service.dart';
import '../../expense/domain/expense.dart';
import '../../expense/domain/expense_query.dart';
import '../../shared/ui/format.dart';

final _month = DateFormat('MMMM yyyy', 'fr_FR');

/// Note de frais des dépenses données (en général la liste filtrée), prête à mettre en PDF.
ExpenseReport reportOf(List<Expense> expenses) {
  final sorted = [...expenses]
    ..sort((a, b) {
      final da = a.effectiveDate, db = b.effectiveDate;
      if (da == null || db == null) return da == null ? 1 : -1;
      return da.compareTo(db);
    });
  return ExpenseReport(
    title: _title(sorted),
    totals: formatTotals(totalsByCurrency(sorted)),
    lines: [
      for (final e in sorted)
        ReportLine(
          date: formatDate(e.effectiveDate),
          merchant: e.merchant ?? 'Justificatif sans nom',
          category: e.category?.label ?? '—',
          total: formatAmount(e.amountTotal, e.currency),
          vat: e.amountVat == null
              ? '—'
              : formatAmount(e.amountVat, e.currency),
          caption: [
            formatDate(e.effectiveDate),
            e.merchant ?? 'Justificatif sans nom',
            formatAmount(e.amountTotal, e.currency),
          ].join(' · '),
          imagePath: e.processedPath ?? e.originalPath,
        ),
    ],
  );
}

String _title(List<Expense> sorted) {
  final dates = sorted.map((e) => e.effectiveDate).whereType<DateTime>();
  if (dates.isEmpty) return 'Note de frais';
  final first = dates.first, last = dates.last;
  return first.year == last.year && first.month == last.month
      ? 'Note de frais — ${_month.format(first)}'
      : 'Note de frais du ${formatDate(first)} au ${formatDate(last)}';
}

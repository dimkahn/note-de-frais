import 'package:intl/intl.dart';

import '../domain/expense.dart';

final _date = DateFormat('d MMM yyyy', 'fr_FR');

String formatDate(DateTime? d) => d == null ? 'Date inconnue' : _date.format(d);

/// "1234.50" + "EUR" → "1 234,50 EUR" (sans passer par un double).
String formatAmount(String? amount, String? currency) {
  if (amount == null) return '—';
  final negative = amount.startsWith('-');
  final parts = amount.replaceFirst('-', '').split('.');
  final units = parts.first.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ' ',
  );
  final cents = parts.length > 1 ? parts[1] : '00';
  final symbol = switch (currency) {
    'EUR' => '€',
    'USD' => r'$',
    'GBP' => '£',
    null => '',
    _ => currency,
  };
  return '${negative ? '-' : ''}$units,$cents $symbol'.trim();
}

String formatTotals(Map<String, String> totals) => totals.isEmpty
    ? '—'
    : totals.entries.map((t) => formatAmount(t.value, t.key)).join(' · ');

String statusLabel(Expense e) => switch (e.syncState) {
  SyncState.pendingUpload => 'En attente d\'envoi',
  SyncState.pendingDelete => 'Suppression en attente',
  _ => e.status.label,
};

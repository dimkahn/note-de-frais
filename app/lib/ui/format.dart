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

enum BadgeTone { waiting, attention }

typedef StatusBadge = ({String label, BadgeTone tone});

/// Statut à signaler sur une dépense (`null` : rien à signaler).
/// Sans serveur, il n'y a ni envoi ni analyse automatique : seule la saisie manuelle compte.
StatusBadge? statusBadge(Expense e, {required bool withServer}) {
  final failed =
      e.status == ProcessingStatus.failed ||
      e.status == ProcessingStatus.extractionFailed;
  if (!withServer) {
    if (failed) return (label: e.status.label, tone: BadgeTone.attention);
    if (e.prefilled) return (label: 'À vérifier', tone: BadgeTone.waiting);
    return needsManualEntry(e)
        ? (label: 'À compléter', tone: BadgeTone.attention)
        : null;
  }
  if (e.status == ProcessingStatus.done && e.syncState == SyncState.synced) {
    return null;
  }
  final label = switch (e.syncState) {
    SyncState.pendingUpload when withServer => 'En attente d\'envoi',
    SyncState.pendingDelete when withServer => 'Suppression en attente',
    _ => e.status.label,
  };
  return (label: label, tone: failed ? BadgeTone.attention : BadgeTone.waiting);
}

/// Sans serveur : le montant n'a pas encore été saisi à la main.
bool needsManualEntry(Expense e) => e.amountTotal == null;

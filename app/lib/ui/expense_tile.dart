import 'package:flutter/material.dart';

import '../domain/expense.dart';
import 'format.dart';
import 'receipt_image.dart';

class ExpenseTile extends StatelessWidget {
  const ExpenseTile({super.key, required this.expense, required this.onTap});

  final Expense expense;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = [
      formatDate(expense.effectiveDate),
      if (expense.category != null) expense.category!.label,
      if (expense.city != null) expense.city!,
    ].join(' · ');
    return ListTile(
      onTap: onTap,
      minVerticalPadding: 12,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox.square(
          dimension: 56,
          child: ReceiptImage(expense: expense),
        ),
      ),
      title: Text(
        expense.merchant ?? 'Justificatif sans nom',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
          if (expense.status != ProcessingStatus.done ||
              expense.syncState != SyncState.synced)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: _StatusBadge(expense: expense),
            ),
        ],
      ),
      trailing: Text(
        formatAmount(expense.amountTotal, expense.currency),
        style: theme.textTheme.titleMedium?.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.expense});

  final Expense expense;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final failed =
        expense.status == ProcessingStatus.failed ||
        expense.status == ProcessingStatus.extractionFailed;
    final pending =
        expense.status == ProcessingStatus.pending ||
        expense.syncState != SyncState.synced;
    final (icon, color) = failed
        ? (Icons.error_outline, scheme.error)
        : pending
        ? (Icons.schedule, scheme.tertiary)
        : (Icons.check_circle_outline, scheme.primary);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(statusLabel(expense), style: TextStyle(color: color)),
      ],
    );
  }
}

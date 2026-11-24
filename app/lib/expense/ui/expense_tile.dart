import 'package:flutter/material.dart';

import '../domain/expense.dart';
import '../../shared/ui/format.dart';
import 'category_style.dart';
import 'status_badge.dart';
import 'receipt_image.dart';
import '../../shared/ui/theme.dart';

class ExpenseTile extends StatelessWidget {
  const ExpenseTile({
    super.key,
    required this.expense,
    required this.onTap,
    required this.withServer,
  });

  final Expense expense;
  final VoidCallback onTap;

  /// Un serveur est configuré : envoi et analyse automatique sont attendus.
  final bool withServer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final badge = statusBadge(expense, withServer: withServer);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Card(clipBehavior: Clip.antiAlias, child: _tile(theme, badge)),
    );
  }

  Widget _tile(ThemeData theme, StatusBadge? badge) {
    final subtitle = [
      formatDate(expense.effectiveDate),
      if (expense.category != null) expense.category!.label,
      if (expense.city != null) expense.city!,
    ].join(' · ');
    return ListTile(
      onTap: onTap,
      minVerticalPadding: 12,
      leading: SizedBox.square(
        dimension: 58,
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox.square(
                dimension: 52,
                child: ReceiptImage(expense: expense),
              ),
            ),
            // Pastille du type, détourée de la couleur de la carte pour se détacher de la photo.
            Positioned(
              right: 0,
              bottom: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: theme.colorScheme.surfaceContainerLow,
                    width: 2,
                  ),
                ),
                child: CategoryBadge(category: expense.category, size: 22),
              ),
            ),
          ],
        ),
      ),
      title: Text(
        expense.merchant ?? 'Justificatif sans nom',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleMedium,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
          if (badge != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: _StatusBadge(badge: badge),
            ),
        ],
      ),
      trailing: Text(
        formatAmount(expense.amountTotal, expense.currency),
        style: amountStyle(theme.textTheme.titleMedium),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.badge});

  final StatusBadge badge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (badge.tone) {
      BadgeTone.attention => (Icons.error_outline, scheme.error),
      BadgeTone.waiting => (Icons.schedule, scheme.tertiary),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(badge.label, style: TextStyle(color: color)),
      ],
    );
  }
}

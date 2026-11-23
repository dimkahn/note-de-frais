import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/expense_repository.dart';
import '../domain/expense.dart';
import '../domain/expense_query.dart';
import 'capture.dart';
import 'expense_detail_screen.dart';
import 'expense_tile.dart';
import 'format.dart';
import 'theme.dart';
import 'ticket.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  ExpenseQuery _query = const ExpenseQuery();
  GroupBy _groupBy = GroupBy.month;

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<ExpenseRepository>();
    final filtered = _query.apply(repo.expenses);
    final groups = groupExpenses(filtered, _groupBy);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => scanReceipt(context, repo),
        icon: const Icon(Icons.document_scanner_outlined),
        label: const Text('Scanner'),
      ),
      body: RefreshIndicator(
        onRefresh: repo.sync,
        child: CustomScrollView(
          slivers: [
            SliverAppBar.large(
              title: const Text('Dépenses'),
              actions: [
                if (repo.settings.isConfigured) _SyncButton(repo: repo),
              ],
            ),
            SliverToBoxAdapter(child: _TotalBanner(expenses: filtered)),
            SliverToBoxAdapter(
              child: _FilterBar(
                query: _query,
                groupBy: _groupBy,
                cities: _citiesOf(repo.expenses),
                onQuery: (q) => setState(() => _query = q),
                onGroupBy: (g) => setState(() => _groupBy = g),
              ),
            ),
            if (filtered.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyState(filtered: repo.expenses.isNotEmpty),
              )
            else
              for (final group in groups) ...[
                if (_groupBy != GroupBy.none)
                  SliverToBoxAdapter(child: _GroupHeader(group: group)),
                SliverList.builder(
                  itemCount: group.expenses.length,
                  itemBuilder: (context, i) {
                    final e = group.expenses[i];
                    return ExpenseTile(
                      key: ValueKey(e.id),
                      expense: e,
                      withServer: repo.settings.isConfigured,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ExpenseDetailScreen(expenseId: e.id),
                        ),
                      ),
                    );
                  },
                ),
              ],
            const SliverToBoxAdapter(child: SizedBox(height: 96)),
          ],
        ),
      ),
    );
  }

  static List<String> _citiesOf(List<Expense> expenses) =>
      (expenses
            .map((e) => e.city)
            .whereType<String>()
            .where((c) => c.trim().isNotEmpty)
            .toSet()
            .toList())
        ..sort();
}

class _SyncButton extends StatelessWidget {
  const _SyncButton({required this.repo});

  final ExpenseRepository repo;

  @override
  Widget build(BuildContext context) {
    if (repo.isSyncing) {
      return const Padding(
        padding: EdgeInsets.all(14),
        child: SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    final offline = repo.lastReport?.offline ?? false;
    return IconButton(
      tooltip: offline ? 'Hors-ligne — réessayer' : 'Synchroniser',
      icon: Icon(offline ? Icons.cloud_off_outlined : Icons.sync),
      onPressed: repo.sync,
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.query,
    required this.groupBy,
    required this.cities,
    required this.onQuery,
    required this.onGroupBy,
  });

  final ExpenseQuery query;
  final GroupBy groupBy;
  final List<String> cities;
  final ValueChanged<ExpenseQuery> onQuery;
  final ValueChanged<GroupBy> onGroupBy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SearchBar(
            hintText: 'Rechercher un commerçant, une ville…',
            leading: const Icon(Icons.search),
            onChanged: (t) => onQuery(query.copyWith(text: t)),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _MenuChip<ExpenseCategory>(
                  label: query.category?.label ?? 'Type',
                  selected: query.category != null,
                  options: {for (final c in ExpenseCategory.values) c: c.label},
                  onSelected: (c) => onQuery(
                    c == null
                        ? query.copyWith(clearCategory: true)
                        : query.copyWith(category: c),
                  ),
                ),
                const SizedBox(width: 8),
                _MenuChip<String>(
                  label: query.city ?? 'Lieu',
                  selected: query.city != null,
                  options: {for (final c in cities) c: c},
                  onSelected: (c) => onQuery(
                    c == null
                        ? query.copyWith(clearCity: true)
                        : query.copyWith(city: c),
                  ),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: Text(
                    query.from == null
                        ? 'Période'
                        : '${formatDate(query.from)} → ${formatDate(query.to)}',
                  ),
                  selected: query.from != null,
                  onSelected: (_) => _pickPeriod(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'Regrouper par',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(width: 12),
              DropdownButton<GroupBy>(
                value: groupBy,
                onChanged: (g) => onGroupBy(g ?? groupBy),
                items: [
                  for (final g in GroupBy.values)
                    DropdownMenuItem(value: g, child: Text(g.label)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickPeriod(BuildContext context) async {
    if (query.from != null) {
      onQuery(query.copyWith(clearPeriod: true));
      return;
    }
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 1),
      helpText: 'Période',
    );
    if (range != null) {
      onQuery(query.copyWith(from: range.start, to: range.end));
    }
  }
}

/// Puce de filtre ouvrant un menu ; une seconde sélection de la même valeur retire le filtre.
class _MenuChip<T> extends StatelessWidget {
  const _MenuChip({
    required this.label,
    required this.selected,
    required this.options,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final Map<T, String> options;
  final ValueChanged<T?> onSelected;

  @override
  Widget build(BuildContext context) => MenuAnchor(
    menuChildren: [
      if (selected)
        MenuItemButton(
          onPressed: () => onSelected(null),
          child: const Text('Tous'),
        ),
      for (final entry in options.entries)
        MenuItemButton(
          onPressed: () => onSelected(entry.key),
          child: Text(entry.value),
        ),
    ],
    builder: (context, controller, _) => FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: options.isEmpty
          ? null
          : (_) => controller.isOpen ? controller.close() : controller.open(),
    ),
  );
}

/// Le total, présenté comme un ticket de caisse : l'élément signature de l'application.
class _TotalBanner extends StatelessWidget {
  const _TotalBanner({required this.expenses});

  final List<Expense> expenses;

  @override
  Widget build(BuildContext context) {
    if (expenses.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final on = theme.colorScheme.onPrimary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: TicketCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'TOTAL',
              style: theme.textTheme.labelMedium?.copyWith(
                color: on.withValues(alpha: 0.8),
                letterSpacing: 2,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              formatTotals(totalsByCurrency(expenses)),
              style: amountStyle(theme.textTheme.headlineMedium)
                  ?.copyWith(color: on, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            Text(
              '${expenses.length} dépense${expenses.length > 1 ? 's' : ''}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: on.withValues(alpha: 0.85),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.group});

  final ExpenseGroup group;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${group.label.toUpperCase()} · ${group.count}',
              style: theme.textTheme.labelMedium?.copyWith(
                color: muted,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            formatTotals(group.totals),
            style: amountStyle(theme.textTheme.labelLarge)
                ?.copyWith(color: muted),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.filtered});

  final bool filtered;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 40,
            backgroundColor: Theme.of(context).colorScheme.primary
                .withValues(alpha: 0.10),
            child: Icon(
              filtered
                  ? Icons.filter_alt_off_outlined
                  : Icons.receipt_long_outlined,
              size: 40,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            filtered
                ? 'Aucune dépense ne correspond aux filtres'
                : 'Photographiez votre premier justificatif',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (!filtered) ...[
            const SizedBox(height: 8),
            const Text(
              'Il est recadré et lu automatiquement : vous n\'avez plus qu\'à vérifier.',
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    ),
  );
}

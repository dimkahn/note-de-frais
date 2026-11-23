import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/expense_repository.dart';
import '../domain/expense.dart';
import '../domain/money.dart';
import 'capture.dart';
import 'export_button.dart';
import 'format.dart';
import 'receipt_image.dart';

class ExpenseDetailScreen extends StatelessWidget {
  const ExpenseDetailScreen({super.key, required this.expenseId});

  final String expenseId;

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<ExpenseRepository>();
    final expense = repo.byId(expenseId);
    if (expense == null || expense.deleted) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Dépense supprimée')),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(expense.merchant ?? 'Justificatif'),
        actions: [
          ExportButton(
            title: expense.merchant ?? 'Justificatif',
            imagePaths: [?(expense.processedPath ?? expense.originalPath)],
          ),
          IconButton(
            tooltip: 'Ajuster le cadrage et le filtre',
            icon: const Icon(Icons.crop_rotate),
            onPressed: () => readjustReceipt(context, repo, expense),
          ),
          IconButton(
            tooltip: 'Supprimer',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmDelete(context, repo, expense),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth > 840;
          final withServer = repo.withServer;
          final viewer = _ReceiptViewer(
            expense: expense,
            withServer: withServer,
          );
          final form = _ExpenseForm(
            key: ValueKey('${expense.id}-${expense.serverUpdatedAt}'),
            expense: expense,
            withServer: withServer,
          );
          return wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: viewer),
                    Expanded(child: SingleChildScrollView(child: form)),
                  ],
                )
              : ListView(
                  children: [
                    SizedBox(
                      height: constraints.maxHeight * 0.5,
                      child: viewer,
                    ),
                    form,
                  ],
                );
        },
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    ExpenseRepository repo,
    Expense e,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer cette dépense ?'),
        content: const Text('Elle sera retirée de tous vos appareils.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok ?? false) {
      await repo.delete(e.id);
      if (context.mounted) Navigator.pop(context);
    }
  }
}

/// Affiche la version traitée ou l'original, avec zoom.
class _ReceiptViewer extends StatefulWidget {
  const _ReceiptViewer({required this.expense, required this.withServer});

  final Expense expense;
  final bool withServer;

  @override
  State<_ReceiptViewer> createState() => _ReceiptViewerState();
}

class _ReceiptViewerState extends State<_ReceiptViewer> {
  bool _original = false;

  @override
  Widget build(BuildContext context) {
    final e = widget.expense;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: SegmentedButton<bool>(
            segments: [
              ButtonSegment(
                value: false,
                label: Text(
                  e.cropped
                      ? 'Recadré · ${e.filter.label}'
                      : 'Traité · ${e.filter.label}',
                ),
                enabled: e.processedPath != null,
              ),
              const ButtonSegment(value: true, label: Text('Original')),
            ],
            selected: {_original || e.processedPath == null},
            onSelectionChanged: (s) => setState(() => _original = s.first),
          ),
        ),
        if (widget.withServer && e.status == ProcessingStatus.pending)
          const LinearProgressIndicator(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainer,
                child: InteractiveViewer(
                  maxScale: 6,
                  child: Center(
                    child: ReceiptImage(
                      expense: e,
                      showOriginal: _original,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ExpenseForm extends StatefulWidget {
  const _ExpenseForm({
    super.key,
    required this.expense,
    required this.withServer,
  });

  final Expense expense;
  final bool withServer;

  @override
  State<_ExpenseForm> createState() => _ExpenseFormState();
}

class _ExpenseFormState extends State<_ExpenseForm> {
  final _formKey = GlobalKey<FormState>();
  late final _merchant = TextEditingController(text: widget.expense.merchant);
  late final _amount = TextEditingController(
    text: widget.expense.amountTotal?.replaceAll('.', ','),
  );
  late final _vat = TextEditingController(
    text: widget.expense.amountVat?.replaceAll('.', ','),
  );
  late final _currency = TextEditingController(
    text: widget.expense.currency ?? 'EUR',
  );
  late final _city = TextEditingController(text: widget.expense.city);
  late final _country = TextEditingController(text: widget.expense.country);
  late final _address = TextEditingController(text: widget.expense.address);
  late final _payment = TextEditingController(
    text: widget.expense.paymentMethod,
  );
  late final _description = TextEditingController(
    text: widget.expense.description,
  );
  late ExpenseCategory? _category = widget.expense.category;
  late DateTime? _date = widget.expense.expenseDate;

  @override
  void dispose() {
    for (final c in [
      _merchant,
      _amount,
      _vat,
      _currency,
      _city,
      _country,
      _address,
      _payment,
      _description,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.expense;
    return Form(
      key: _formKey,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (e.processingError != null && e.status != ProcessingStatus.done)
              Card.outlined(
                margin: const EdgeInsets.only(bottom: 16),
                child: ListTile(
                  leading: Icon(
                    Icons.info_outline,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: Text(e.status.label),
                  subtitle: Text(e.processingError!),
                ),
              ),
            if (e.status == ProcessingStatus.notIncluded)
              const Card.outlined(
                margin: EdgeInsets.only(bottom: 16),
                child: ListTile(
                  leading: Icon(Icons.auto_awesome_outlined),
                  title: Text('Analyse IA incluse avec Premium'),
                  subtitle: Text(
                    'Le justificatif est recadré et sauvegardé en ligne ; '
                    'les informations restent celles lues sur l\'appareil ou saisies.',
                  ),
                ),
              ),
            if (e.prefilled && !e.userEdited)
              const Card.outlined(
                margin: EdgeInsets.only(bottom: 16),
                child: ListTile(
                  leading: Icon(Icons.document_scanner_outlined),
                  title: Text('Lu automatiquement sur l\'appareil'),
                  subtitle: Text(
                    'Vérifiez le montant, la TVA, la date et le commerçant, '
                    'puis enregistrez.',
                  ),
                ),
              )
            else if (!widget.withServer && needsManualEntry(e))
              const Card.outlined(
                margin: EdgeInsets.only(bottom: 16),
                child: ListTile(
                  leading: Icon(Icons.edit_note),
                  title: Text('Analyse automatique indisponible'),
                  subtitle: Text(
                    'Aucun serveur configuré : saisissez les informations '
                    'ci-dessous. Le justificatif sera analysé si vous '
                    'configurez un serveur plus tard.',
                  ),
                ),
              ),
            if (e.userEdited)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'Corrigé manuellement : une nouvelle extraction ne modifiera pas ces champs.',
                ),
              ),
            _field(_merchant, 'Commerçant'),
            DropdownButtonFormField<ExpenseCategory>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Type de dépense'),
              items: [
                for (final c in ExpenseCategory.values)
                  DropdownMenuItem(value: c, child: Text(c.label)),
              ],
              onChanged: (c) => setState(() => _category = c),
            ),
            const SizedBox(height: 12),
            InputDecorator(
              decoration: const InputDecoration(labelText: 'Date'),
              child: InkWell(
                onTap: _pickDate,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(formatDate(_date)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: _field(_amount, 'Montant TTC', amount: true),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _field(
                    _currency,
                    'Devise',
                    validator: _validateCurrency,
                  ),
                ),
              ],
            ),
            _field(_vat, 'TVA', amount: true),
            Row(
              children: [
                Expanded(flex: 2, child: _field(_city, 'Ville')),
                const SizedBox(width: 12),
                Expanded(child: _field(_country, 'Pays')),
              ],
            ),
            _field(_address, 'Adresse'),
            _field(_payment, 'Moyen de paiement'),
            _field(_description, 'Description', maxLines: 3),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check),
              label: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool amount = false,
    int maxLines = 1,
    FormFieldValidator<String>? validator,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(labelText: label),
      keyboardType: amount
          ? const TextInputType.numberWithOptions(decimal: true)
          : null,
      validator: amount ? _validateAmount : validator,
    ),
  );

  String? _validateAmount(String? v) =>
      (v == null || v.trim().isEmpty || normalizeAmount(v) != null)
      ? null
      : 'Montant invalide (ex. 12,50)';

  String? _validateCurrency(String? v) =>
      (v == null || v.isEmpty || RegExp(r'^[A-Za-z]{3}$').hasMatch(v.trim()))
      ? null
      : 'Code ISO (EUR)';

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    String? text(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();
    final edited = Expense(
      id: widget.expense.id,
      merchant: text(_merchant),
      category: _category,
      expenseDate: _date,
      amountTotal: normalizeAmount(_amount.text),
      amountVat: normalizeAmount(_vat.text),
      currency: text(_currency)?.toUpperCase(),
      city: text(_city),
      country: text(_country)?.toUpperCase(),
      address: text(_address),
      paymentMethod: text(_payment),
      description: text(_description),
    );
    await context.read<ExpenseRepository>().edit(edited);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Dépense enregistrée')));
    }
  }
}

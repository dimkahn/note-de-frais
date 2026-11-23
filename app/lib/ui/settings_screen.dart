import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/expense_api.dart';
import '../data/expense_repository.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final ExpenseRepository _repo = context.read<ExpenseRepository>();
  late final _url = TextEditingController(text: _repo.settings.baseUrl);
  late final _token = TextEditingController(text: _repo.settings.token);
  bool _obscure = true;

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final report = context.watch<ExpenseRepository>().lastReport;
    return Scaffold(
      appBar: AppBar(title: const Text('Réglages')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Adresse du serveur',
              hintText: 'http://192.168.1.10:8080',
              helperText:
                  'Optionnel : sans serveur, tout fonctionne sur l\'appareil, '
                  'sauf l\'analyse automatique des justificatifs.',
              helperMaxLines: 2,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _token,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: 'Jeton d\'accès (optionnel)',
              suffixIcon: IconButton(
                tooltip: _obscure ? 'Afficher' : 'Masquer',
                icon: Icon(
                  _obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _save,
            child: const Text('Enregistrer et synchroniser'),
          ),
          const SizedBox(height: 24),
          if (report != null)
            ListTile(
              leading: Icon(
                report.offline
                    ? Icons.cloud_off_outlined
                    : Icons.cloud_done_outlined,
              ),
              title: Text(
                report.offline
                    ? 'Serveur injoignable'
                    : 'Dernière synchronisation réussie',
              ),
              subtitle: Text(
                [
                  '${report.pushed} envoyée(s), ${report.pulled} reçue(s)',
                  ...report.errors,
                ].join('\n'),
              ),
            ),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Vos justificatifs restent sur l\'appareil'),
            subtitle: Text(
              'Les originaux sont conservés localement (et sur le serveur s\'il est configuré) ; '
              'le recadrage et l\'extraction ne les modifient jamais.',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    await _repo.saveSettings(
      ServerSettings(baseUrl: _url.text, token: _token.text),
    );
    if (!mounted) return;
    // Onglet de la navigation principale : rien à fermer, on confirme sur place.
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Réglages enregistrés')));
  }
}

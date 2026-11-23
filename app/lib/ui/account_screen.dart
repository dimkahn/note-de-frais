import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/account_repository.dart';
import '../data/auth_api.dart';
import '../data/expense_api.dart';
import '../data/expense_repository.dart';
import '../domain/account.dart';

/// Se connecter à un compte existant, ou en créer un.
enum SignInMode { signIn, register }

/// Page « Compte » : connexion / inscription, ou état du compte connecté.
/// L'app reste pleinement utilisable sans compte.
class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AccountRepository>().session;
    return Scaffold(
      appBar: AppBar(title: const Text('Compte')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (session == null) ...[
            const _SignInForm(),
            const SizedBox(height: 24),
            const _PlansOverview(),
            const SizedBox(height: 8),
            const ListTile(
              leading: Icon(Icons.phone_android_outlined),
              title: Text('L\'app fonctionne aussi sans compte'),
              subtitle: Text(
                'Scan, lecture des tickets et exports se font sur l\'appareil. '
                'Un compte ajoute la sauvegarde en ligne et la synchronisation.',
              ),
            ),
          ] else ...[
            _AccountSummary(account: session.account),
            const _BiometricLoginSetting(),
            const _SyncStatus(),
          ],
          const SizedBox(height: 8),
          const _AdvancedSection(),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Vos justificatifs restent sur l\'appareil'),
            subtitle: Text(
              'Les originaux sont conservés localement (et en ligne si vous êtes connecté) ; '
              'le recadrage et l\'extraction ne les modifient jamais.',
            ),
          ),
        ],
      ),
    );
  }
}

class _SignInForm extends StatefulWidget {
  const _SignInForm();

  @override
  State<_SignInForm> createState() => _SignInFormState();
}

class _SignInFormState extends State<_SignInForm> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  var _mode = SignInMode.signIn;
  var _obscure = true;
  var _busy = false;
  String? _error;

  bool get _registering => _mode == SignInMode.register;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final account = context.watch<AccountRepository>();
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<SignInMode>(
            segments: const [
              ButtonSegment(
                value: SignInMode.signIn,
                label: Text('Se connecter'),
              ),
              ButtonSegment(
                value: SignInMode.register,
                label: Text('Créer un compte'),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() {
              _mode = s.single;
              _error = null;
            }),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(labelText: 'E-mail'),
            validator: (v) =>
                v != null && RegExp(r'^\S+@\S+\.\S+$').hasMatch(v.trim())
                ? null
                : 'Adresse e-mail invalide',
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _password,
            obscureText: _obscure,
            autofillHints: [
              _registering ? AutofillHints.newPassword : AutofillHints.password,
            ],
            decoration: InputDecoration(
              labelText: 'Mot de passe',
              helperText: _registering ? '10 caractères minimum' : null,
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
            validator: (v) {
              if (v == null || v.isEmpty) return 'Mot de passe requis';
              if (_registering && v.length < 10) {
                return 'Au moins 10 caractères';
              }
              return null;
            },
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_registering ? 'Créer mon compte' : 'Se connecter'),
          ),
          if (account.biometricAvailable && account.biometricEnabled) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.fingerprint),
              label: const Text('Se connecter avec l\'empreinte'),
              onPressed: _busy ? null : () => _run(account.loginWithBiometrics),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final account = context.read<AccountRepository>();
    await _run(
      () => _registering
          ? account.register(_email.text, _password.text)
          : account.login(_email.text, _password.text),
    );
  }

  Future<void> _run(Future<void> Function() authenticate) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    String? error;
    try {
      await authenticate();
    } on AuthException catch (e) {
      error = e.message;
    } on OfflineException {
      error =
          'Serveur injoignable : vérifiez la connexion et l\'adresse '
          '(section « Avancé »).';
    } on ApiException catch (e) {
      error = 'Erreur du serveur (${e.statusCode}), réessayez plus tard.';
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
  }
}

/// Les deux offres, côte à côte.
class _PlansOverview extends StatelessWidget {
  const _PlansOverview();

  @override
  Widget build(BuildContext context) => const IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _PlanCard(
            title: 'Gratuit',
            features: [
              '100 Mo de sauvegarde en ligne',
              'Synchronisation entre vos appareils',
            ],
          ),
        ),
        SizedBox(width: 12),
        Expanded(
          child: _PlanCard(
            title: 'Premium',
            features: [
              '1 Go de sauvegarde en ligne',
              'Lecture des justificatifs par analyse IA',
            ],
            badge: 'Bientôt disponible',
          ),
        ),
      ],
    ),
  );
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.title, required this.features, this.badge});

  final String title;
  final List<String> features;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: text.titleMedium),
            const SizedBox(height: 8),
            for (final f in features)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(f, style: text.bodyMedium),
              ),
            if (badge != null) ...[
              const SizedBox(height: 4),
              Chip(label: Text(badge!), visualDensity: VisualDensity.compact),
            ],
          ],
        ),
      ),
    );
  }
}

class _AccountSummary extends StatelessWidget {
  const _AccountSummary({required this.account});

  final Account account;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ListTile(
        leading: const Icon(Icons.account_circle_outlined),
        title: Text(account.email),
        subtitle: Text('Offre ${account.plan.label}'),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        icon: const Icon(Icons.logout),
        label: const Text('Se déconnecter'),
        onPressed: () => context.read<AccountRepository>().logout(),
      ),
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'Après la déconnexion, vos dépenses restent sur cet appareil.',
          textAlign: TextAlign.center,
        ),
      ),
    ],
  );
}

/// Connexion par empreinte, proposée seulement si l'appareil a une biométrie.
class _BiometricLoginSetting extends StatelessWidget {
  const _BiometricLoginSetting();

  @override
  Widget build(BuildContext context) {
    final account = context.watch<AccountRepository>();
    if (!account.biometricAvailable) return const SizedBox.shrink();
    if (account.biometricEnabled) {
      return TextButton.icon(
        icon: const Icon(Icons.fingerprint),
        label: const Text('Désactiver l\'empreinte'),
        onPressed: account.disableBiometricLogin,
      );
    }
    return OutlinedButton.icon(
      icon: const Icon(Icons.fingerprint),
      label: const Text('Activer la connexion par empreinte'),
      onPressed: () => _enable(context, account),
    );
  }

  Future<void> _enable(BuildContext context, AccountRepository account) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await account.enableBiometricLogin();
    } on OfflineException {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Serveur injoignable : empreinte non activée.'),
        ),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Erreur du serveur (${e.statusCode}).')),
      );
    }
  }
}

class _SyncStatus extends StatelessWidget {
  const _SyncStatus();

  @override
  Widget build(BuildContext context) {
    final report = context.watch<ExpenseRepository>().lastReport;
    if (report == null) return const SizedBox.shrink();
    return ListTile(
      leading: Icon(
        report.offline ? Icons.cloud_off_outlined : Icons.cloud_done_outlined,
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
    );
  }
}

/// Réglages techniques, rarement utiles : l'adresse du serveur.
class _AdvancedSection extends StatefulWidget {
  const _AdvancedSection();

  @override
  State<_AdvancedSection> createState() => _AdvancedSectionState();
}

class _AdvancedSectionState extends State<_AdvancedSection> {
  late final _url = TextEditingController(
    text: context.read<AccountRepository>().serverAddressOverride,
  );

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExpansionTile(
    title: const Text('Avancé'),
    tilePadding: EdgeInsets.zero,
    childrenPadding: const EdgeInsets.only(bottom: 16),
    children: [
      TextField(
        controller: _url,
        keyboardType: TextInputType.url,
        decoration: InputDecoration(
          labelText: 'Adresse du serveur',
          hintText: 'Vide : adresse par défaut',
          helperText:
              'Adresse utilisée : '
              '${context.watch<AccountRepository>().settings.baseUrl}',
        ),
      ),
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerRight,
        child: FilledButton.tonal(
          onPressed: _save,
          child: const Text('Enregistrer l\'adresse'),
        ),
      ),
    ],
  );

  Future<void> _save() async {
    await context.read<AccountRepository>().saveServerAddress(_url.text);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Adresse enregistrée')));
  }
}

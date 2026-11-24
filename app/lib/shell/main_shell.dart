import 'package:flutter/material.dart';

import '../document/ui/document_screen.dart';
import '../document/ui/documents_screen.dart';
import '../expense/ui/home_screen.dart';
import '../account/ui/account_screen.dart';
import '../scan/domain/scan_session.dart';
import '../scan/ui/capture.dart';

/// Navigation principale : un onglet par usage. L'état de chaque onglet est conservé.
/// Lance un scan dans le mode donné et enregistre ce qui a été scanné.
typedef ShellScanner = Future<SavedScan?> Function(
  BuildContext context,
  ScanMode mode,
);

class MainShell extends StatefulWidget {
  const MainShell({super.key, this.scan = scanAndSave});

  final ShellScanner scan;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _tab = 0;

  static const _tabs = [
    (Icons.receipt_long_outlined, Icons.receipt_long, 'Dépenses'),
    (Icons.layers_outlined, Icons.layers, 'Documents'),
    (Icons.account_circle_outlined, Icons.account_circle, 'Compte'),
  ];

  /// Depuis l'onglet Documents, on scanne un document ; sinon un ticket.
  Future<void> _scan() async {
    final mode = _tab == 1 ? ScanMode.document : ScanMode.ticket;
    final saved = await widget.scan(context, mode);
    if (!mounted) return;
    switch (saved) {
      case SavedExpense():
        setState(() => _tab = 0);
      case SavedDocument(:final document):
        setState(() => _tab = 1);
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DocumentScreen(documentId: document.id),
          ),
        );
      case null:
        break;
    }
  }

  Widget _tabButton(int index) {
    final (icon, selectedIcon, label) = _tabs[index];
    return _TabButton(
      icon: icon,
      selectedIcon: selectedIcon,
      label: label,
      selected: _tab == index,
      onTap: () => setState(() => _tab = index),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(
      index: _tab,
      children: const [HomeScreen(), DocumentsScreen(), AccountScreen()],
    ),
    floatingActionButton: _ScanButton(onPressed: _scan),
    floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    bottomNavigationBar: BottomAppBar(
      shape: const CircularNotchedRectangle(),
      notchMargin: 6,
      padding: EdgeInsets.zero,
      height: 72,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Row(
        children: [
          Expanded(child: Row(children: [_tabButton(0), _tabButton(1)])),
          const SizedBox(width: 88), // place du bouton Scanner
          Expanded(child: Row(children: [_tabButton(2)])),
        ],
      ),
    ),
  );
}

/// Le geste principal de l'app : gros bouton rond, au centre de la barre.
class _ScanButton extends StatelessWidget {
  const _ScanButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 68,
    child: FloatingActionButton(
      tooltip: 'Scanner',
      onPressed: onPressed,
      shape: const CircleBorder(),
      elevation: 3,
      child: const Icon(Icons.document_scanner_outlined, size: 30),
    ),
  );
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = selected ? scheme.onSurface : scheme.onSurfaceVariant;
    return Expanded(
      child: Semantics(
        selected: selected,
        button: true,
        child: InkWell(
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 56,
                height: 30,
                decoration: BoxDecoration(
                  color: selected
                      ? scheme.primary.withValues(alpha: 0.14)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(selected ? selectedIcon : icon, color: color),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

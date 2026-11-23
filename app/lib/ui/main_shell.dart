import 'package:flutter/material.dart';

import 'documents_screen.dart';
import 'home_screen.dart';
import 'settings_screen.dart';

/// Navigation principale : un onglet par usage. L'état de chaque onglet est conservé.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(
      index: _tab,
      children: const [HomeScreen(), DocumentsScreen(), SettingsScreen()],
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _tab,
      onDestinationSelected: (i) => setState(() => _tab = i),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.receipt_long_outlined),
          selectedIcon: Icon(Icons.receipt_long),
          label: 'Dépenses',
        ),
        NavigationDestination(
          icon: Icon(Icons.layers_outlined),
          selectedIcon: Icon(Icons.layers),
          label: 'Documents',
        ),
        NavigationDestination(
          icon: Icon(Icons.tune_outlined),
          selectedIcon: Icon(Icons.tune),
          label: 'Réglages',
        ),
      ],
    ),
  );
}

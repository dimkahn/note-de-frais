import 'package:flutter/material.dart';

import '../domain/expense.dart';

/// Couleur et icône d'un type de dépense, pour le reconnaître d'un coup d'œil.
///
/// Teintes foncées pour qu'un pictogramme blanc reste lisible (≥ 3:1), en mode clair comme sombre.
typedef CategoryStyle = ({IconData icon, Color color});

CategoryStyle categoryStyle(ExpenseCategory? category) {
  final (icon, color) = switch (category) {
    ExpenseCategory.restaurant => (Icons.restaurant, const Color(0xFFD9480F)),
    ExpenseCategory.hotel => (Icons.hotel, const Color(0xFF9C36B5)),
    ExpenseCategory.transport => (
      Icons.directions_bus,
      const Color(0xFF087F5B),
    ),
    ExpenseCategory.train => (Icons.train, const Color(0xFF1971C2)),
    ExpenseCategory.avion => (Icons.flight, const Color(0xFF0B7285)),
    ExpenseCategory.taxi => (Icons.local_taxi, const Color(0xFFB35C00)),
    ExpenseCategory.carburant => (
      Icons.local_gas_station,
      const Color(0xFFC92A2A),
    ),
    ExpenseCategory.peage => (Icons.toll, const Color(0xFF5F3DC4)),
    ExpenseCategory.parking => (Icons.local_parking, const Color(0xFF2B8A3E)),
    ExpenseCategory.fournitures => (
      Icons.shopping_bag,
      const Color(0xFFC2255C),
    ),
    ExpenseCategory.telecom => (Icons.phone_iphone, const Color(0xFF5C940D)),
    ExpenseCategory.autre => (Icons.category, const Color(0xFF495057)),
    null => (Icons.help_outline, const Color(0xFF868E96)),
  };
  return (icon: icon, color: color);
}

/// Pastille ronde colorée portant l'icône du type.
class CategoryBadge extends StatelessWidget {
  const CategoryBadge({super.key, required this.category, this.size = 24});

  final ExpenseCategory? category;
  final double size;

  @override
  Widget build(BuildContext context) {
    final style = categoryStyle(category);
    return Semantics(
      label: category?.label ?? 'Type non renseigné',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: style.color, shape: BoxShape.circle),
        child: Icon(style.icon, size: size * 0.6, color: Colors.white),
      ),
    );
  }
}

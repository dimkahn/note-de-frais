import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Élément signature : une carte au bord inférieur déchiré en dents de scie, comme un ticket de caisse.
class TicketCard extends StatelessWidget {
  const TicketCard({
    super.key,
    required this.child,
    this.color,
    this.padding = const EdgeInsets.fromLTRB(20, 18, 20, 26),
  });

  final Widget child;
  final Color? color;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => ClipPath(
    clipper: const TornEdgeClipper(),
    child: ColoredBox(
      color: color ?? Theme.of(context).colorScheme.primary,
      child: Padding(padding: padding, child: child),
    ),
  );
}

/// Coins supérieurs arrondis, bord inférieur en dents de scie.
class TornEdgeClipper extends CustomClipper<Path> {
  const TornEdgeClipper({this.tooth = 12, this.radius = 20});

  final double tooth;
  final double radius;

  @override
  Path getClip(Size size) {
    final path = Path()
      ..moveTo(0, radius)
      ..quadraticBezierTo(0, 0, radius, 0)
      ..lineTo(size.width - radius, 0)
      ..quadraticBezierTo(size.width, 0, size.width, radius)
      ..lineTo(size.width, size.height - tooth / 2);
    final count = math.max(1, (size.width / tooth).floor());
    final step = size.width / count;
    for (var i = count; i > 0; i--) {
      final x = i * step;
      path
        ..lineTo(x - step / 2, size.height)
        ..lineTo(x - step, size.height - tooth / 2);
    }
    return path..close();
  }

  @override
  bool shouldReclip(TornEdgeClipper old) =>
      old.tooth != tooth || old.radius != radius;
}

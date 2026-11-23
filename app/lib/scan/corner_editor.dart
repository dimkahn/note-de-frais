import 'package:flutter/material.dart';

import '../domain/quad.dart';

/// Affiche [child] (la photo) avec le contour éditable : 4 poignées déplaçables, zone hors
/// document assombrie et loupe pendant le déplacement pour viser précisément le coin.
class CornerEditor extends StatefulWidget {
  const CornerEditor({
    super.key,
    required this.imageAspectRatio,
    required this.quad,
    required this.onChanged,
    required this.child,
  });

  /// Largeur / hauteur de la photo affichée.
  final double imageAspectRatio;
  final Quad quad;
  final ValueChanged<Quad> onChanged;
  final Widget child;

  @override
  State<CornerEditor> createState() => _CornerEditorState();
}

class _CornerEditorState extends State<CornerEditor> {
  static const _handleSize = 56.0;
  static const _labels = [
    'Coin haut gauche',
    'Coin haut droit',
    'Coin bas droit',
    'Coin bas gauche',
  ];

  late Quad _quad = widget.quad;
  int? _dragging;

  @override
  void didUpdateWidget(CornerEditor old) {
    super.didUpdateWidget(old);
    if (_dragging == null && widget.quad != old.quad) _quad = widget.quad;
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return LayoutBuilder(
      builder: (context, constraints) {
        final rect = _fittedRect(constraints.biggest);
        Offset toScreen(Corner c) =>
            rect.topLeft + Offset(c.x * rect.width, c.y * rect.height);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fromRect(rect: rect, child: widget.child),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: QuadPainter(_quad, rect, color: color),
                ),
              ),
            ),
            if (_dragging != null)
              _loupe(toScreen(_quad.corners[_dragging!]), color),
            for (var i = 0; i < 4; i++)
              Positioned(
                left: toScreen(_quad.corners[i]).dx - _handleSize / 2,
                top: toScreen(_quad.corners[i]).dy - _handleSize / 2,
                child: Semantics(
                  label: _labels[i],
                  hint: 'Faire glisser pour ajuster le cadrage',
                  child: GestureDetector(
                    key: ValueKey('corner-$i'),
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (_) => setState(() => _dragging = i),
                    onPanUpdate: (d) => _move(i, d.delta, rect),
                    onPanEnd: (_) => setState(() => _dragging = null),
                    onPanCancel: () => setState(() => _dragging = null),
                    child: SizedBox.square(
                      dimension: _handleSize,
                      child: Center(
                        child: _Handle(color: color, active: _dragging == i),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  void _move(int index, Offset delta, Rect rect) {
    final c = _quad.corners[index];
    final moved = _quad.moveCorner(
      index,
      Corner(c.x + delta.dx / rect.width, c.y + delta.dy / rect.height),
    );
    if (moved == _quad) return;
    setState(() => _quad = moved);
    widget.onChanged(moved);
  }

  /// Loupe au-dessus du doigt, centrée sur le coin déplacé.
  Widget _loupe(Offset corner, Color color) {
    const size = 110.0;
    return Positioned(
      left: corner.dx - size / 2,
      top: corner.dy - size - 48,
      child: RawMagnifier(
        size: const Size.square(size),
        magnificationScale: 2.5,
        focalPointOffset: const Offset(0, size / 2 + 48),
        decoration: MagnifierDecoration(
          shape: CircleBorder(side: BorderSide(color: color, width: 3)),
        ),
      ),
    );
  }

  Rect _fittedRect(Size box) {
    final boxRatio = box.width / box.height;
    final size = widget.imageAspectRatio > boxRatio
        ? Size(box.width, box.width / widget.imageAspectRatio)
        : Size(box.height * widget.imageAspectRatio, box.height);
    return Offset(
          (box.width - size.width) / 2,
          (box.height - size.height) / 2,
        ) &
        size;
  }
}

class _Handle extends StatelessWidget {
  const _Handle({required this.color, required this.active});

  final Color color;
  final bool active;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 120),
    width: active ? 30 : 24,
    height: active ? 30 : 24,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Colors.white,
      border: Border.all(color: color, width: 4),
      boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black38)],
    ),
  );
}

/// Dessine le contour et assombrit ce qui est hors du document. Réutilisé par l'écran caméra.
class QuadPainter extends CustomPainter {
  QuadPainter(
    this.quad,
    this.imageRect, {
    required this.color,
    this.fillProgress = 0,
  });

  final Quad quad;
  final Rect imageRect;
  final Color color;

  /// 0..1 : remplissage progressif pendant l'attente de stabilité (déclenchement auto).
  final double fillProgress;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addPolygon([
        for (final c in quad.corners)
          imageRect.topLeft +
              Offset(c.x * imageRect.width, c.y * imageRect.height),
      ], true);
    final outside = Path.combine(
      PathOperation.difference,
      Path()..addRect(imageRect),
      path,
    );
    canvas.drawPath(
      outside,
      Paint()..color = Colors.black.withValues(alpha: 0.45),
    );
    if (fillProgress > 0) {
      canvas.drawPath(
        path,
        Paint()..color = color.withValues(alpha: 0.35 * fillProgress),
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(QuadPainter old) =>
      old.quad != quad ||
      old.imageRect != imageRect ||
      old.fillProgress != fillProgress ||
      old.color != color;
}

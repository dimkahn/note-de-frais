import 'quad.dart';

/// Décide du déclenchement automatique : le contour doit rester immobile (à [tolerance] près,
/// en fraction de l'image) pendant [holdFor]. Ne déclenche qu'une fois jusqu'à [reset].
final class StabilityTracker {
  StabilityTracker({
    this.holdFor = const Duration(milliseconds: 1200),
    this.tolerance = 0.02,
    this.dropout = const Duration(milliseconds: 400),
  });

  final Duration holdFor;
  final double tolerance;

  /// Durée pendant laquelle le document peut ne plus être détecté (image floue, reflet) sans
  /// relancer l'attente : la détection sur le flux vidéo rate souvent une image isolée.
  final Duration dropout;

  Quad? _anchor;
  DateTime? _since;
  DateTime? _last;
  DateTime? _seen;
  bool _fired = false;

  /// Avancement de 0 à 1 vers le déclenchement (pour l'animation du contour).
  double get progress {
    if (_since == null || _last == null) return 0;
    final ratio =
        _last!.difference(_since!).inMicroseconds / holdFor.inMicroseconds;
    return ratio.clamp(0.0, 1.0);
  }

  /// Retourne `true` au moment où la capture doit être déclenchée.
  bool update(Quad? quad, DateTime now) {
    if (quad == null) {
      final seen = _seen;
      if (seen == null || now.difference(seen) > dropout) {
        _anchor = null;
        _since = null;
        _last = null;
      }
      return false;
    }
    _seen = now;
    _last = now;
    if (_anchor == null || quad.maxShift(_anchor!) > tolerance) {
      _anchor = quad;
      _since = now;
      return false;
    }
    if (_fired || now.difference(_since!) < holdFor) return false;
    _fired = true;
    return true;
  }

  void reset() {
    _anchor = null;
    _since = null;
    _last = null;
    _seen = null;
    _fired = false;
  }
}

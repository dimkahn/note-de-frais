import 'quad.dart';

/// Décide du déclenchement automatique : le contour doit rester immobile (à [tolerance] près,
/// en fraction de l'image) pendant [holdFor]. Ne déclenche qu'une fois jusqu'à [reset].
///
/// Un contour différent ne remplace le contour suivi que si celui-ci n'a plus été vu depuis
/// [dropout] : une image isolée où la détection saute sur un autre objet ne relance pas l'attente.
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

  /// Depuis quand un autre contour est vu sans interruption (il remplacera le contour suivi).
  DateTime? _otherSince;

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
      if (seen == null || now.difference(seen) > dropout) _forget();
      return false;
    }
    if (_anchor != null && quad.maxShift(_anchor!) > tolerance) {
      _otherSince ??= now;
      if (now.difference(_seen!) <= dropout) return false;
      _anchor = null;
    }
    if (_anchor == null) {
      _anchor = quad;
      _since = _otherSince ?? now;
    }
    _otherSince = null;
    _seen = now;
    _last = now;
    if (_fired || now.difference(_since!) < holdFor) return false;
    _fired = true;
    return true;
  }

  void reset() {
    _forget();
    _seen = null;
    _fired = false;
  }

  void _forget() {
    _anchor = null;
    _since = null;
    _last = null;
    _otherSince = null;
  }
}

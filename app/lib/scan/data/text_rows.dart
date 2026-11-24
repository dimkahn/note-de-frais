/// Morceau de texte reconnu, avec sa position dans l'image (pixels).
final class TextFragment {
  const TextFragment(
    this.text, {
    required this.left,
    required this.top,
    required this.bottom,
  });

  final String text;
  final double left;
  final double top;
  final double bottom;

  double get center => (top + bottom) / 2;
  double get height => bottom - top;
}

/// Reconstitue les lignes d'un ticket : l'OCR rend souvent les colonnes séparément (libellés puis
/// montants). Deux fragments sont sur la même ligne si leurs centres verticaux sont à moins d'une
/// demi-hauteur ; chaque ligne est lue de gauche à droite.
String assembleRows(List<TextFragment> fragments) {
  final byTop = [...fragments]..sort((a, b) => a.center.compareTo(b.center));
  final rows = <List<TextFragment>>[];
  for (final f in byTop) {
    final row = rows.isEmpty ? null : rows.last;
    final anchor = row?.first;
    if (anchor != null &&
        (f.center - anchor.center).abs() < anchor.height / 2) {
      row!.add(f);
    } else {
      rows.add([f]);
    }
  }
  return rows
      .map(
        (row) => (row..sort((a, b) => a.left.compareTo(b.left)))
            .map((f) => f.text)
            .join(' '),
      )
      .join('\n');
}

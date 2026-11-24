import 'package:flutter_test/flutter_test.dart';
import 'package:note_de_frais/scan/data/text_rows.dart';

void main() {
  test(
    'remet sur une même ligne un libellé et son montant lus en colonnes',
    () {
      // L'OCR rend la colonne des libellés, puis celle des montants.
      final fragments = [
        const TextFragment('PAIN', left: 10, top: 100, bottom: 120),
        const TextFragment('TOTAL TTC', left: 10, top: 140, bottom: 160),
        const TextFragment('1,20', left: 300, top: 102, bottom: 121),
        const TextFragment('5,70 €', left: 300, top: 139, bottom: 158),
      ];

      expect(assembleRows(fragments), 'PAIN 1,20\nTOTAL TTC 5,70 €');
    },
  );

  test('garde des lignes distinctes même légèrement inclinées', () {
    final fragments = [
      const TextFragment('B', left: 10, top: 130, bottom: 150),
      const TextFragment('A', left: 10, top: 100, bottom: 120),
      const TextFragment('A2', left: 200, top: 106, bottom: 126),
    ];

    expect(assembleRows(fragments), 'A A2\nB');
  });

  test('aucun fragment, aucun texte', () {
    expect(assembleRows(const []), '');
  });
}

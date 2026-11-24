import 'package:flutter_test/flutter_test.dart';
import 'package:note_de_frais/scan/domain/receipt_parser.dart';

/// Texte réellement rendu par ML Kit (sortie d'`assembleRows`) sur le ticket de l'île de loisirs de
/// Cergy, le 23/11/2026. Erreurs d'OCR conservées : « 304. O0 » pour le total, « TIC » pour TTC…
const ticketCergyLuParMlKit = '''
ILE DE LOISIRS OE CERNY PONTOSE
CAISSE MULTISPORT
JUSTIFICATIF DE PAIEMENT
A PRESENTER SUR L'ACTIVITE
ARTICLES PRIX TTC
PASS IND CLUB N 26 304.00 A
19.00 Eur. x 16 Unita#233;
TOTAL (EURO) 304. O0
CB 304.00
NUMERO : 513269##W*88
DONT TVA HT TVA TIC
A 20,00 % 253,33 50,67 304,00
Rue des Etangs
95001 Cerey Pontoise Cedex France
Tel : 01 30 30 21 55
Siret : 2595006270003 NAF : 9311Z
TVA : FR69259500627
TOUTE SORTIE EST DEFINITIVE
TICKET NUMERO WS-4550
NUMERO DE SAISTE EN REGIE 271131
ENREGISTRE LE 10/10/2026 09:39:32
IHPRIME LE 10/10/2026 09:39:32
CAISSIER 194 (CS)
LOGICIEL OXYGENO V3.11
''';

void main() {
  const parser = ReceiptParser();

  const supermarche = '''
CARREFOUR MARKET
12 RUE DE LA PAIX
75002 PARIS
TEL 01 23 45 67 89
14/03/2026 12:41
PAIN 1,20
FROMAGE 4,50
SOUS-TOTAL 5,70
TOTAL TTC 5,70 €
TVA 5,5% 0,30
ESPECES 20,00
RENDU 14,30
''';

  group('montant total', () {
    test('lit le total TTC plutôt que les espèces données', () {
      final guess = parser.parse(supermarche);

      expect(guess.amountTotal, '5.70');
    });

    test('retient le plus grand des totaux (TTC plutôt que HT)', () {
      final guess = parser.parse('TOTAL HT 10,00\nTVA 20% 2,00\nTOTAL 12,00');

      expect(guess.amountTotal, '12.00');
    });

    test('lit le montant sur la ligne suivant le mot-clé', () {
      final guess = parser.parse('NET A PAYER\n42,50');

      expect(guess.amountTotal, '42.50');
    });

    test('sans mot-clé, retient le plus grand montant hors espèces', () {
      final guess = parser.parse('Café 2,50\nCroissant 1,30\nEspèces 10,00');

      expect(guess.amountTotal, '2.50');
    });

    test(
      "ne lit pas la ligne d'article sous un en-tête de colonne « PRIX TTC »",
      () {
        final guess = parser.parse('''
ILE DE LOISIRS DE CERGY PONTOISE
ARTICLES PRIX TTC *
PASS IND CLUB N 26 304.00 A
19.00 Eur. x 16 Unit
TOTAL (EURO) 304.00
CB 304.00
* DONT TVA HT TVA TTC
A 20.00 % 253.33 50.67 304.00
''');

        expect(guess.amountTotal, '304.00');
      },
    );

    test(
      'lit le total du ticket de Cergy tel que lu par l\'OCR du téléphone',
      () {
        final guess = parser.parse(ticketCergyLuParMlKit);

        expect(guess.amountTotal, '304.00');
      },
    );

    test('lit sur la ligne suivante un montant mal reconnu par l\'OCR', () {
      expect(
        parser.parse('NET A PAYER\n42. 5O\nARTICLE 99,00').amountTotal,
        '42.50',
      );
    });

    test('ne prend pas « 3, 25 pièces » pour un montant', () {
      expect(
        parser.parse('Article 3, 25 pièces\nCafé 2,50').amountTotal,
        '2.50',
      );
    });

    test('lit sur la ligne suivante un montant suivi de « TTC »', () {
      expect(
        parser.parse('NET A PAYER\n42,50 TTC\nARTICLE 99,00').amountTotal,
        '42.50',
      );
    });

    test('lit le montant suivi de la devise sur la ligne suivante', () {
      expect(parser.parse('NET A PAYER\n42,50 €').amountTotal, '42.50');
    });

    test('comprend les séparateurs de milliers', () {
      expect(parser.parse('TOTAL 1 234,56').amountTotal, '1234.56');
      expect(parser.parse('TOTAL 1.234,56').amountTotal, '1234.56');
      expect(parser.parse('Total 1,234.56').amountTotal, '1234.56');
    });

    test('ne prend pas une date ou un pourcentage pour un montant', () {
      final guess = parser.parse('14.03.26\nREMISE 10,00%\nArticle 3,00');

      expect(guess.amountTotal, '3.00');
    });
  });

  group('TVA', () {
    test('lit le montant de TVA sans le confondre avec le taux', () {
      expect(parser.parse(supermarche).amountVat, '0.30');
    });

    test('additionne plusieurs taux de TVA', () {
      final guess = parser.parse(
        'TVA 5,5% 0,30\nTVA 20% 1,70\nTOTAL TTC 25,00',
      );

      expect(guess.amountVat, '2.00');
    });
  });

  group('date', () {
    test('lit une date numérique', () {
      expect(parser.parse(supermarche).expenseDate, DateTime(2026, 3, 14));
      expect(
        parser.parse('Le 05.11.25 à 9h').expenseDate,
        DateTime(2025, 11, 5),
      );
      expect(parser.parse('2026-01-31').expenseDate, DateTime(2026, 1, 31));
    });

    test('lit une date en toutes lettres', () {
      expect(
        parser.parse('Paris, le 3 février 2026').expenseDate,
        DateTime(2026, 2, 3),
      );
      expect(parser.parse('12 AOUT 2025').expenseDate, DateTime(2025, 8, 12));
    });

    test('ignore une date impossible', () {
      expect(parser.parse('32/13/2026').expenseDate, isNull);
    });
  });

  group('devise et commerçant', () {
    test('reconnaît la devise', () {
      expect(parser.parse(supermarche).currency, 'EUR');
      expect(parser.parse('TOTAL CHF 12.50').currency, 'CHF');
      expect(parser.parse('Total £8.20').currency, 'GBP');
      expect(parser.parse('TOTAL 5,70').currency, isNull);
    });

    test('prend la première ligne significative comme commerçant', () {
      expect(parser.parse(supermarche).merchant, 'CARREFOUR MARKET');
      expect(
        parser.parse('BIENVENUE\n*** TICKET ***\nLe  Bistrot  du Port\n'),
        isA<ReceiptGuess>().having(
          (g) => g.merchant,
          'merchant',
          'Le Bistrot du Port',
        ),
      );
    });
  });

  test('un texte vide ne donne rien', () {
    final guess = parser.parse('');

    expect(guess.isEmpty, isTrue);
  });
}

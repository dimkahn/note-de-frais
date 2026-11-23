import 'package:flutter_test/flutter_test.dart';
import 'package:note_de_frais/domain/expense.dart';
import 'package:note_de_frais/domain/quad.dart';
import 'package:note_de_frais/domain/receipt_parser.dart';

void main() {
  const serverJson = {
    'id': '0b6f5d3c-6a39-4c6e-9f0e-2d7f3f2b9a11',
    'merchant': 'Le Bistrot',
    'category': 'RESTAURANT',
    'expenseDate': '2026-03-10',
    'amountTotal': 42.5,
    'amountVat': 3.86,
    'currency': 'EUR',
    'city': 'Paris',
    'country': 'FR',
    'address': '1 rue de Rivoli',
    'paymentMethod': 'CB',
    'description': 'Déjeuner',
    'userEdited': false,
    'filter': 'ENHANCE',
    'cropped': true,
    'corners': '0.1,0.1,0.9,0.1,0.9,0.9,0.1,0.9',
    'hasProcessedImage': true,
    'status': 'DONE',
    'processingError': null,
    'deleted': false,
    'createdAt': '2026-03-10T12:00:00Z',
    'updatedAt': '2026-03-10T12:01:00Z',
  };

  group('Expense', () {
    test('se construit depuis le JSON du serveur', () {
      final e = Expense.fromServerJson(serverJson);

      expect(e.merchant, 'Le Bistrot');
      expect(e.category, ExpenseCategory.restaurant);
      expect(e.expenseDate, DateTime(2026, 3, 10));
      expect(e.amountTotal, '42.50');
      expect(e.status, ProcessingStatus.done);
      expect(e.serverUpdatedAt, DateTime.utc(2026, 3, 10, 12, 1));
      expect(e.syncState, SyncState.synced);
      expect(e.corners, Quad.inset(0.1));
    });

    test('les montants restent exacts en texte décimal', () {
      final e = Expense.fromServerJson({...serverJson, 'amountTotal': 0.1});

      expect(e.amountTotal, '0.10');
    });

    test('reconnaît une analyse IA non incluse dans l\'offre', () {
      final e = Expense.fromServerJson({
        ...serverJson,
        'status': 'NOT_INCLUDED',
      });

      expect(e.status.code, 'NOT_INCLUDED');
    });

    test('une catégorie inconnue devient AUTRE', () {
      final e = Expense.fromServerJson({...serverJson, 'category': 'NOUVELLE'});

      expect(e.category, ExpenseCategory.autre);
    });

    test('aller-retour base locale sans perte', () {
      final e = Expense.fromServerJson(serverJson).copyWith(
        syncState: SyncState.pendingUpdate,
        originalPath: '/data/x/original.jpg',
        processedPath: '/data/x/processed.jpg',
      );

      final back = Expense.fromDb(e.toDb());

      expect(back, e);
    });

    test(
      'le corps de mise à jour contient uniquement les champs éditables',
      () {
        final body = Expense.fromServerJson(serverJson).toUpdateJson();

        expect(body.keys, containsAll(['merchant', 'category', 'amountTotal']));
        expect(body.containsKey('status'), isFalse);
        expect(body['expenseDate'], '2026-03-10');
        expect(body['amountTotal'], '42.50');
      },
    );

    test('un brouillon attend son envoi au serveur', () {
      final e = Expense.draft(
        id: 'abc',
        originalPath: '/o.jpg',
        filter: ImageFilter.scanBw,
      );

      expect(e.syncState, SyncState.pendingUpload);
      expect(e.status, ProcessingStatus.pending);
      expect(e.filter, ImageFilter.scanBw);
    });
  });

  group('lecture sur l\'appareil', () {
    final draft = Expense.draft(
      id: 'd',
      originalPath: '/tmp/d.jpg',
      filter: ImageFilter.enhance,
    );
    final guess = ReceiptGuess(
      merchant: 'Carrefour',
      expenseDate: DateTime(2026, 3, 14),
      amountTotal: '5.70',
      amountVat: '0.30',
      currency: 'EUR',
    );

    test('complète les champs vides et marque la dépense pré-remplie', () {
      final e = draft.withDeviceGuess(guess);

      expect(e.merchant, 'Carrefour');
      expect(e.expenseDate, DateTime(2026, 3, 14));
      expect(e.amountTotal, '5.70');
      expect(e.amountVat, '0.30');
      expect(e.currency, 'EUR');
      expect(e.prefilled, isTrue);
      expect(e.userEdited, isFalse);
    });

    test(
      'ne change pas l\'état de synchronisation (aucun envoi de correction)',
      () {
        final synced = draft.copyWith(syncState: SyncState.synced);

        expect(synced.withDeviceGuess(guess).syncState, SyncState.synced);
      },
    );

    test('ne remplace jamais un champ déjà rempli', () {
      final e = draft.copyWith(amountTotal: '9.99').withDeviceGuess(guess);

      expect(e.amountTotal, '9.99');
      expect(e.merchant, 'Carrefour');
    });

    test('sans effet sur une dépense corrigée à la main', () {
      final edited = draft.withEditedFields(draft);

      expect(edited.withDeviceGuess(guess), edited);
    });

    test('sans effet quand l\'analyse serveur est terminée', () {
      final done = draft.copyWith(status: ProcessingStatus.done);

      expect(done.withDeviceGuess(guess), done);
    });

    test('une correction manuelle valide le pré-remplissage', () {
      final prefilled = draft.withDeviceGuess(guess);

      final edited = prefilled.withEditedFields(prefilled);

      expect(edited.prefilled, isFalse);
      expect(edited.userEdited, isTrue);
    });

    test('le pré-remplissage survit à la base locale', () {
      final prefilled = draft.withDeviceGuess(guess);

      expect(Expense.fromDb(prefilled.toDb()).prefilled, isTrue);
    });
  });
}

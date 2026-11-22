import 'package:flutter_test/flutter_test.dart';
import 'package:note_de_frais/domain/expense.dart';

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
    });

    test('les montants restent exacts en texte décimal', () {
      final e = Expense.fromServerJson({...serverJson, 'amountTotal': 0.1});

      expect(e.amountTotal, '0.10');
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
}

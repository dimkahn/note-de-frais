import 'package:flutter_test/flutter_test.dart';
import 'package:note_de_frais/domain/expense.dart';
import 'package:note_de_frais/domain/receipt_parser.dart';
import 'package:note_de_frais/ui/format.dart';

void main() {
  test('formate un montant à la française sans passer par un double', () {
    expect(formatAmount('1234.50', 'EUR'), '1 234,50 €');
    expect(formatAmount('0.10', 'CHF'), '0,10 CHF');
    expect(formatAmount(null, 'EUR'), '—');
  });

  test('affiche les totaux de plusieurs devises', () {
    expect(
      formatTotals({'CHF': '30.00', 'EUR': '35.50'}),
      '30,00 CHF · 35,50 €',
    );
    expect(formatTotals({}), '—');
  });

  group('statut affiché', () {
    final unsent = Expense.draft(
      id: 'a',
      originalPath: '/tmp/a.jpg',
      filter: ImageFilter.enhance,
    );

    test('avec serveur, signale une dépense pas encore envoyée', () {
      expect(statusBadge(unsent, withServer: true), (
        label: 'En attente d\'envoi',
        tone: BadgeTone.waiting,
      ));
    });

    test(
      'avec serveur, rien à signaler pour une dépense traitée et synchronisée',
      () {
        final done = unsent.copyWith(
          status: ProcessingStatus.done,
          syncState: SyncState.synced,
        );

        expect(statusBadge(done, withServer: true), isNull);
      },
    );

    test('avec serveur, une extraction échouée est à compléter', () {
      final failed = unsent.copyWith(
        status: ProcessingStatus.extractionFailed,
        syncState: SyncState.synced,
      );

      expect(statusBadge(failed, withServer: true), (
        label: 'À compléter',
        tone: BadgeTone.attention,
      ));
    });

    test(
      'sans serveur, une dépense sans montant est à compléter à la main',
      () {
        expect(statusBadge(unsent, withServer: false), (
          label: 'À compléter',
          tone: BadgeTone.attention,
        ));
      },
    );

    test('sans serveur, rien à signaler une fois le montant saisi', () {
      final filled = unsent.withEditedFields(
        unsent.copyWith(amountTotal: '12.50'),
      );

      expect(statusBadge(filled, withServer: false), isNull);
    });

    test('sans serveur, rien à signaler pour une dépense traitée en attente de synchro', () {
      final done = unsent.copyWith(
        status: ProcessingStatus.done,
        amountTotal: '12.50',
        syncState: SyncState.pendingUpdate,
      );

      expect(statusBadge(done, withServer: false), isNull);
    });

    test('sans serveur, un échec de traitement reste signalé', () {
      final failed = unsent.copyWith(
        status: ProcessingStatus.extractionFailed,
        syncState: SyncState.pendingUpdate,
      );

      expect(statusBadge(failed, withServer: false), (
        label: 'À compléter',
        tone: BadgeTone.attention,
      ));
    });

    test(
      'sans serveur, un pré-remplissage par lecture locale est à vérifier',
      () {
        final prefilled = unsent.withDeviceGuess(
          const ReceiptGuess(amountTotal: '5.70'),
        );

        expect(statusBadge(prefilled, withServer: false), (
          label: 'À vérifier',
          tone: BadgeTone.waiting,
        ));
      },
    );
  });
}

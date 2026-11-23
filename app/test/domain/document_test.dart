import 'package:flutter_test/flutter_test.dart';
import 'package:note_de_frais/domain/document.dart';
import 'package:note_de_frais/domain/expense.dart';
import 'package:note_de_frais/domain/quad.dart';

void main() {
  final created = DateTime.utc(2026, 11, 23, 9, 30);
  ScannedPage page(String id) => ScannedPage(
    id: id,
    originalPath: '/docs/$id/original.jpg',
    processedPath: '/docs/$id/processed.jpg',
    corners: Quad.inset(0.1),
    filter: ImageFilter.enhance,
  );

  ScannedDocument empty() =>
      ScannedDocument.create(id: 'doc', createdAt: created);

  test('un nouveau document porte un titre daté et aucune page', () {
    final doc = empty();

    expect(doc.title, 'Document du 23/11/2026');
    expect(doc.pages, isEmpty);
    expect(doc.deleted, isFalse);
  });

  test('ajoute les pages dans l\'ordre de prise', () {
    final later = created.add(const Duration(minutes: 1));

    final doc = empty()
        .withPage(page('p1'), at: later)
        .withPage(page('p2'), at: later);

    expect(doc.pages.map((p) => p.id), ['p1', 'p2']);
    expect(doc.updatedAt, later);
  });

  test('retire une page sans toucher aux autres', () {
    final doc = empty()
        .withPage(page('p1'), at: created)
        .withPage(page('p2'), at: created)
        .withPage(page('p3'), at: created);

    final updated = doc.withoutPage('p2', at: created);

    expect(updated.pages.map((p) => p.id), ['p1', 'p3']);
  });

  test(
    'réajuste une page sans changer son original ni sa place dans le document',
    () {
      final later = created.add(const Duration(minutes: 5));
      final doc = empty()
          .withPage(page('p1'), at: created)
          .withPage(page('p2'), at: created)
          .withPage(page('p3'), at: created);

      final updated = doc.withPageAdjusted(
        'p2',
        corners: Quad.inset(0.2),
        filter: ImageFilter.scanBw,
        processedPath: '/docs/p2/processed-v2.jpg',
        at: later,
      );

      expect(updated.pages.map((p) => p.id), ['p1', 'p2', 'p3']);
      final p2 = updated.pages[1];
      expect(p2.originalPath, '/docs/p2/original.jpg');
      expect(p2.processedPath, '/docs/p2/processed-v2.jpg');
      expect(p2.corners, Quad.inset(0.2));
      expect(p2.filter, ImageFilter.scanBw);
      expect(updated.pages[0].processedPath, '/docs/p1/processed.jpg');
      expect(updated.updatedAt, later);
    },
  );

  test('renomme sans accepter un titre vide', () {
    final doc = empty();

    expect(doc.renamed('  Bail  ', at: created).title, 'Bail');
    expect(doc.renamed('   ', at: created).title, doc.title);
  });

  test('la couverture est la première page', () {
    final doc = empty()
        .withPage(page('p1'), at: created)
        .withPage(page('p2'), at: created);

    expect(doc.cover?.id, 'p1');
    expect(empty().cover, isNull);
  });

  test('les pages ne se modifient pas de l\'extérieur', () {
    final doc = empty().withPage(page('p1'), at: created);

    expect(() => doc.pages.add(page('x')), throwsUnsupportedError);
  });

  group('état de synchronisation', () {
    ScannedDocument synced() => ScannedDocument(
      id: 'doc',
      title: 'Bail',
      createdAt: created,
      updatedAt: created,
      syncState: SyncState.synced,
      pages: [
        ScannedPage(
          id: 'p1',
          originalPath: '/docs/p1/original.jpg',
          processedPath: '/docs/p1/processed.jpg',
          corners: Quad.inset(0.1),
          filter: ImageFilter.enhance,
          syncState: SyncState.synced,
          renderVersion: 1,
        ),
      ],
    );

    test('un nouveau document et ses nouvelles pages attendent l\'envoi', () {
      final doc = empty().withPage(page('p1'), at: created);

      expect(doc.syncState, SyncState.pendingUpload);
      expect(doc.pages.single.syncState, SyncState.pendingUpload);
    });

    test('un document déjà envoyé qui change attend sa mise à jour', () {
      final doc = synced();

      expect(
        doc.renamed('Contrat', at: created).syncState,
        SyncState.pendingUpdate,
      );
      expect(
        doc.withoutPage('p1', at: created).syncState,
        SyncState.pendingUpdate,
      );
      expect(
        doc.withPage(page('p2'), at: created).syncState,
        SyncState.pendingUpdate,
      );
    });

    test('un document jamais envoyé reste à envoyer après un changement', () {
      expect(
        empty().renamed('Contrat', at: created).syncState,
        SyncState.pendingUpload,
      );
    });

    test('la suppression attend d\'être propagée', () {
      expect(
        synced().markDeleted(at: created).syncState,
        SyncState.pendingDelete,
      );
      expect(
        empty().markDeleted(at: created).syncState,
        SyncState.pendingDelete,
      );
    });

    test('une page envoyée puis réajustée attend son nouveau rendu', () {
      final adjusted = synced().withPageAdjusted(
        'p1',
        corners: Quad.inset(0.2),
        filter: ImageFilter.sharpen,
        processedPath: '/docs/p1/processed-v2.jpg',
        at: created,
      );

      expect(adjusted.pages.single.syncState, SyncState.pendingReprocess);
      expect(adjusted.pages.single.renderVersion, 1);
    });

    test('une page jamais envoyée puis réajustée reste à envoyer', () {
      final adjusted = empty()
          .withPage(page('p1'), at: created)
          .withPageAdjusted(
            'p1',
            corners: Quad.inset(0.2),
            filter: ImageFilter.sharpen,
            processedPath: '/docs/p1/processed-v2.jpg',
            at: created,
          );

      expect(adjusted.pages.single.syncState, SyncState.pendingUpload);
    });
  });
}

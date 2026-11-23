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
}

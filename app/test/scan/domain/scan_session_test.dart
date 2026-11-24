import 'package:flutter_test/flutter_test.dart';
import 'package:note_de_frais/expense/domain/expense.dart';
import 'package:note_de_frais/scan/domain/quad.dart';
import 'package:note_de_frais/scan/domain/rotation.dart';
import 'package:note_de_frais/scan/domain/scan_session.dart';

CapturedPage _page(String path) => CapturedPage(photoPath: path);

void main() {
  test('une session commence vide, dans le mode demandé', () {
    const session = ScanSession(ScanMode.document);

    expect(session.pages, isEmpty);
    expect(session.mode, ScanMode.document);
    expect(session.canAdd, isTrue);
  });

  test('en mode Document, les pages s\'enchaînent dans l\'ordre de prise', () {
    final session = const ScanSession(ScanMode.document)
        .withPage(_page('/a.jpg'))
        .withPage(_page('/b.jpg'));

    expect(session.pages.map((p) => p.photoPath), ['/a.jpg', '/b.jpg']);
    expect(session.canAdd, isTrue);
  });

  test('en mode Ticket, une seule page', () {
    final session = const ScanSession(ScanMode.ticket)
        .withPage(_page('/a.jpg'));

    expect(session.canAdd, isFalse);
    expect(() => session.withPage(_page('/b.jpg')), throwsStateError);
  });

  test('retire une page', () {
    final session = const ScanSession(ScanMode.document)
        .withPage(_page('/a.jpg'))
        .withPage(_page('/b.jpg'))
        .withoutPage(0);

    expect(session.pages.map((p) => p.photoPath), ['/b.jpg']);
  });

  test('remplace les réglages d\'une page sans toucher aux autres', () {
    final session = const ScanSession(ScanMode.document)
        .withPage(_page('/a.jpg'))
        .withPage(_page('/b.jpg'));

    final edited = session.withPageReplaced(
      1,
      session.pages[1].copyWith(
        corners: Quad.inset(0.1),
        filter: ImageFilter.scanBw,
        rotation: Rotation.clockwise90,
      ),
    );

    expect(edited.pages[0].corners, isNull);
    expect(edited.pages[1].corners, Quad.inset(0.1));
    expect(edited.pages[1].filter, ImageFilter.scanBw);
    expect(edited.pages[1].rotation, Rotation.clockwise90);
  });

  test('le mode ne change que tant qu\'aucune page n\'est prise', () {
    const empty = ScanSession(ScanMode.ticket);

    expect(empty.withMode(ScanMode.document).mode, ScanMode.document);
    expect(
      () =>
          const ScanSession(ScanMode.document)
              .withPage(_page('/a.jpg'))
              .withMode(ScanMode.ticket),
      throwsStateError,
    );
  });

  test(
    'une page prise est recadrée automatiquement, améliorée, sans rotation',
    () {
      final page = _page('/a.jpg');

      expect(page.corners, isNull);
      expect(page.filter, ImageFilter.enhance);
      expect(page.rotation, Rotation.none);
    },
  );

  test('une page du scanner système est déjà recadrée : cadre sur l\'image entière', () {
    final page = CapturedPage.scanned('/cache/page1.jpg');

    expect(page.photoPath, '/cache/page1.jpg');
    expect(page.corners, Quad.inset(0));
  });

  test(
    'le scanner système prend une page en mode Ticket, sans limite en Document',
    () {
      expect(ScanMode.ticket.pageLimit, 1);
      expect(ScanMode.document.pageLimit, isNull);
    },
  );
}

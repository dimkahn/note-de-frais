import '../../expense/domain/expense.dart';
import 'quad.dart';
import 'rotation.dart';

/// Ce que l'on scanne : un ticket (une page, une dépense) ou un document (plusieurs pages).
enum ScanMode {
  ticket('Ticket'),
  document('Document');

  const ScanMode(this.label);

  final String label;

  /// Pages au plus par passage dans le scanner système (`null` : sans limite).
  int? get pageLimit => this == ticket ? 1 : null;
}

/// Page prise pendant un scan : la photo brute et ses réglages de rendu.
final class CapturedPage {
  const CapturedPage({
    required this.photoPath,
    this.corners,
    this.hint,
    this.filter = ImageFilter.enhance,
    this.rotation = Rotation.none,
  });

  /// Page rendue par le scanner système (ML Kit), déjà recadrée : cadre sur l'image entière.
  factory CapturedPage.scanned(String photoPath) =>
      CapturedPage(photoPath: photoPath, corners: Quad.inset(0));

  final String photoPath;

  /// Contour choisi ; `null` : à détecter sur la photo.
  final Quad? corners;

  /// Contour vu en direct par la caméra, si la détection sur la photo ne trouve rien.
  final Quad? hint;
  final ImageFilter filter;
  final Rotation rotation;

  CapturedPage copyWith({
    Quad? corners,
    ImageFilter? filter,
    Rotation? rotation,
  }) => CapturedPage(
    photoPath: photoPath,
    corners: corners ?? this.corners,
    hint: hint,
    filter: filter ?? this.filter,
    rotation: rotation ?? this.rotation,
  );
}

/// Pages en cours de scan, avant leur enregistrement. Immuable.
final class ScanSession {
  const ScanSession(this.mode, {this.pages = const []});

  final ScanMode mode;
  final List<CapturedPage> pages;

  /// Un ticket n'a qu'une page ; un document autant qu'on veut.
  bool get canAdd => mode == ScanMode.document || pages.isEmpty;

  ScanSession withPage(CapturedPage page) {
    if (!canAdd) throw StateError('Un ticket n\'a qu\'une page');
    return ScanSession(mode, pages: List.unmodifiable([...pages, page]));
  }

  ScanSession withoutPage(int index) =>
      ScanSession(mode, pages: List.unmodifiable([...pages]..removeAt(index)));

  ScanSession withPageReplaced(int index, CapturedPage page) =>
      ScanSession(mode, pages: List.unmodifiable([...pages]..[index] = page));

  /// Le mode se choisit avant la première prise.
  ScanSession withMode(ScanMode mode) {
    if (pages.isNotEmpty) throw StateError('Mode figé après la première prise');
    return ScanSession(mode);
  }
}

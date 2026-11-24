import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../expense/domain/expense.dart';
import '../data/document_scanner.dart';
import '../domain/quad.dart';
import '../domain/scan_session.dart';
import 'adjust_screen.dart';

/// Issue de la revue des pages d'un scan.
sealed class ReviewOutcome {
  const ReviewOutcome();
}

/// Pages validées, rendues sur l'appareil, dans l'ordre.
final class ReviewSaved extends ReviewOutcome {
  const ReviewSaved(this.pages);

  final List<ScanResult> pages;
}

/// Retour à la caméra avec les pages restantes (ajout, retour, dernière page supprimée).
final class ReviewContinue extends ReviewOutcome {
  const ReviewContinue(this.session);

  final ScanSession session;
}

/// Revue des pages prises : une page en grand (glisser pour changer), outils en bas,
/// « Enregistrer » rend chaque page en pleine définition. Les originaux ne sont jamais modifiés.
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({
    super.key,
    required this.session,
    this.compute = inIsolate,
  });

  final ScanSession session;
  final Compute compute;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  // Calculs envoyés à un isolate : méthodes statiques, pour que la fermeture ne capture que
  // ses paramètres (l'état de l'écran n'est pas transmissible entre isolates).
  static Quad? Function() _detectJob(Uint8List bytes) =>
      () => const DocumentScanner().detect(bytes);

  static Uint8List Function() _renderJob(
    Uint8List bytes,
    CapturedPage page,
    Quad corners, {
    ImageFilter? filter,
    required int maxSide,
  }) {
    final chosen = filter ?? page.filter;
    final rotation = page.rotation;
    return () => const DocumentScanner().render(
      bytes,
      corners,
      chosen,
      rotation: rotation,
      maxSide: maxSide,
    );
  }

  static const _previewSide = 1200;
  static const _thumbSide = 240;
  static const _fullSide = 2400;

  late ScanSession _session = widget.session;
  final _pager = PageController();
  int _index = 0;
  bool _showFilters = false;
  bool _saving = false;

  final _photos = <String, Uint8List>{};
  final _previews = Map<CapturedPage, Uint8List>.identity();
  final _thumbs = <(CapturedPage, ImageFilter), Uint8List>{};

  CapturedPage get _page => _session.pages[_index];

  @override
  void initState() {
    super.initState();
    _ensurePreview(0);
  }

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  Future<Uint8List> _photo(String path) async =>
      _photos[path] ??= await File(path).readAsBytes();

  /// Contour de la page : celui choisi, sinon détecté sur la photo, sinon vu en direct,
  /// sinon un cadre en léger retrait (comme l'écran d'ajustement).
  Future<CapturedPage> _withCorners(int index) async {
    final page = _session.pages[index];
    if (page.corners != null) return page;
    final detected = await widget.compute(
      _detectJob(await _photo(page.photoPath)),
    );
    final framed = page.copyWith(
      corners: detected ?? page.hint ?? Quad.inset(0.05),
    );
    if (mounted && identical(_session.pages[index], page)) {
      setState(() => _session = _session.withPageReplaced(index, framed));
    }
    return framed;
  }

  Future<void> _ensurePreview(int index) async {
    final page = await _withCorners(index);
    if (_previews.containsKey(page)) return;
    final jpeg = await widget.compute(
      _renderJob(
        await _photo(page.photoPath),
        page,
        page.corners!,
        maxSide: _previewSide,
      ),
    );
    if (mounted) setState(() => _previews[page] = jpeg);
    if (_showFilters) await _ensureThumbs();
  }

  Future<void> _ensureThumbs() async {
    final page = await _withCorners(_index);
    final bytes = await _photo(page.photoPath);
    for (final filter in ImageFilter.values) {
      if (_thumbs.containsKey((page, filter))) continue;
      final jpeg = await widget.compute(
        _renderJob(
          bytes,
          page,
          page.corners!,
          filter: filter,
          maxSide: _thumbSide,
        ),
      );
      if (!mounted) return;
      setState(() => _thumbs[(page, filter)] = jpeg);
    }
  }

  void _replaceCurrent(CapturedPage page) {
    setState(() => _session = _session.withPageReplaced(_index, page));
    _ensurePreview(_index);
  }

  void _onPageChanged(int index) {
    setState(() => _index = index);
    _ensurePreview(index);
  }

  Future<void> _crop() async {
    final page = await _withCorners(_index);
    if (!mounted) return;
    final result = await Navigator.push<ScanResult>(
      context,
      MaterialPageRoute(
        builder: (_) => AdjustScreen(
          photoPath: page.photoPath,
          initialQuad: page.corners,
          initialFilter: page.filter,
          initialRotation: page.rotation,
          title: 'Recadrer',
          compute: widget.compute,
        ),
      ),
    );
    if (result == null || !mounted) return;
    final adjusted = page.copyWith(
      corners: result.quad,
      filter: result.filter,
      rotation: result.rotation,
    );
    setState(() {
      _session = _session.withPageReplaced(_index, adjusted);
      _previews[adjusted] = result.processedJpeg;
    });
  }

  void _rotate() =>
      _replaceCurrent(_page.copyWith(rotation: _page.rotation.next()));

  void _toggleFilters() {
    setState(() => _showFilters = !_showFilters);
    if (_showFilters) _ensureThumbs();
  }

  void _chooseFilter(ImageFilter filter) =>
      _replaceCurrent(_page.copyWith(filter: filter));

  void _delete() {
    final remaining = _session.withoutPage(_index);
    if (remaining.pages.isEmpty) {
      Navigator.pop(context, ReviewContinue(remaining));
      return;
    }
    final index = _index.clamp(0, remaining.pages.length - 1);
    setState(() {
      _session = remaining;
      _index = index;
    });
    if (_pager.hasClients) _pager.jumpToPage(index);
    _ensurePreview(index);
  }

  void _continue() => Navigator.pop(context, ReviewContinue(_session));

  Future<void> _save() async {
    setState(() => _saving = true);
    final results = <ScanResult>[];
    for (var i = 0; i < _session.pages.length; i++) {
      final page = await _withCorners(i);
      final jpeg = await widget.compute(
        _renderJob(
          await _photo(page.photoPath),
          page,
          page.corners!,
          maxSide: _fullSide,
        ),
      );
      results.add(
        ScanResult(
          photoPath: page.photoPath,
          quad: page.corners!,
          filter: page.filter,
          rotation: page.rotation,
          processedJpeg: jpeg,
        ),
      );
    }
    if (mounted) Navigator.pop(context, ReviewSaved(results));
  }

  @override
  Widget build(BuildContext context) {
    final count = _session.pages.length;
    final document = _session.mode == ScanMode.document;
    return PopScope(
      // Revenir en arrière ramène à la caméra sans perdre les pages prises.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_saving) _continue();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text(document ? 'Page ${_index + 1} / $count' : 'Ticket'),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: PageView.builder(
                  controller: _pager,
                  itemCount: count,
                  onPageChanged: _onPageChanged,
                  itemBuilder: (_, i) => _PagePreview(
                    jpeg: _previews[_session.pages[i]],
                    number: i + 1,
                  ),
                ),
              ),
              if (_showFilters)
                _FilterStrip(
                  thumbs: {
                    for (final f in ImageFilter.values) f: _thumbs[(_page, f)],
                  },
                  selected: _page.filter,
                  onSelected: _chooseFilter,
                ),
              _Toolbar(
                busy: _saving,
                onCrop: _crop,
                onRotate: _rotate,
                onFilters: _toggleFilters,
                filtersOpen: _showFilters,
                onDelete: _delete,
                onAdd: document ? _continue : null,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    label: Text(
                      count > 1
                          ? 'Enregistrer les $count pages'
                          : 'Enregistrer',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PagePreview extends StatelessWidget {
  const _PagePreview({required this.jpeg, required this.number});

  final Uint8List? jpeg;
  final int number;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: jpeg == null
        ? const Center(child: CircularProgressIndicator())
        : Semantics(
            label: 'Aperçu de la page $number',
            image: true,
            child: Image.memory(
              jpeg!,
              fit: BoxFit.contain,
              gaplessPlayback: true,
            ),
          ),
  );
}

/// La page courante sous chaque filtre : on choisit en voyant le résultat.
class _FilterStrip extends StatelessWidget {
  const _FilterStrip({
    required this.thumbs,
    required this.selected,
    required this.onSelected,
  });

  final Map<ImageFilter, Uint8List?> thumbs;
  final ImageFilter selected;
  final ValueChanged<ImageFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return SizedBox(
      height: 132,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          for (final MapEntry(key: filter, value: jpeg) in thumbs.entries)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => onSelected(filter),
                child: SizedBox(
                  width: 76,
                  child: Column(
                    children: [
                      Container(
                        width: 72,
                        height: 88,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: filter == selected ? accent : Colors.white24,
                            width: filter == selected ? 3 : 1,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Semantics(
                          label: 'Aperçu du filtre ${filter.label}',
                          image: true,
                          child: jpeg == null
                              ? const Center(
                                  child: SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              : Image.memory(jpeg, fit: BoxFit.cover),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        filter.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: filter == selected ? accent : Colors.white,
                          fontSize: 12,
                          fontWeight: filter == selected
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.busy,
    required this.onCrop,
    required this.onRotate,
    required this.onFilters,
    required this.filtersOpen,
    required this.onDelete,
    required this.onAdd,
  });

  final bool busy;
  final VoidCallback onCrop;
  final VoidCallback onRotate;
  final VoidCallback onFilters;
  final bool filtersOpen;
  final VoidCallback onDelete;

  /// Mode Document seulement.
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Row(
      children: [
        Expanded(
          child: _Tool(
            icon: Icons.crop,
            label: 'Recadrer',
            onPressed: busy ? null : onCrop,
          ),
        ),
        Expanded(
          child: _Tool(
            icon: Icons.rotate_right,
            label: 'Pivoter',
            onPressed: busy ? null : onRotate,
          ),
        ),
        Expanded(
          child: _Tool(
            icon: Icons.auto_fix_high,
            label: 'Filtres',
            active: filtersOpen,
            onPressed: busy ? null : onFilters,
          ),
        ),
        Expanded(
          child: _Tool(
            icon: Icons.delete_outline,
            label: 'Supprimer',
            onPressed: busy ? null : onDelete,
          ),
        ),
        if (onAdd != null)
          Expanded(
            child: _Tool(
              icon: Icons.add_a_photo_outlined,
              label: 'Ajouter',
              onPressed: busy ? null : onAdd,
            ),
          ),
      ],
    ),
  );
}

class _Tool extends StatelessWidget {
  const _Tool({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? Theme.of(context).colorScheme.primary : Colors.white;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: color,
        minimumSize: const Size(48, 56),
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

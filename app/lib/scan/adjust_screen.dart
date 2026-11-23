import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../domain/expense.dart';
import '../domain/quad.dart';
import 'corner_editor.dart';
import 'document_scanner.dart';

/// Résultat d'un scan validé : la photo brute (non modifiée) et ce qu'il faut pour la traiter.
final class ScanResult {
  const ScanResult({
    required this.photoPath,
    required this.quad,
    required this.filter,
    required this.processedJpeg,
  });

  final String photoPath;
  final Quad quad;
  final ImageFilter filter;

  /// Image recadrée + filtrée calculée sur l'appareil.
  final Uint8List processedJpeg;
}

/// Exécute un calcul lourd hors du thread d'interface (remplaçable dans les tests).
typedef Compute = Future<T> Function<T>(T Function() work);

Future<T> _isolate<T>(T Function() work) => Isolate.run(work);

/// Ajustement des coins et choix du filtre, avec aperçu, comme dans une application de scan.
class AdjustScreen extends StatefulWidget {
  const AdjustScreen({
    super.key,
    required this.photoPath,
    this.initialQuad,
    this.fallbackQuad,
    this.initialFilter = ImageFilter.enhance,
    this.compute = _isolate,
  });

  final String photoPath;

  /// Contour déjà connu (détection en direct ou cadrage précédent) ; sinon détection sur la photo.
  final Quad? initialQuad;

  /// Utilisé si rien n'est détecté sur la photo (ex. contour vu en direct par la caméra).
  final Quad? fallbackQuad;
  final ImageFilter initialFilter;
  final Compute compute;

  @override
  State<AdjustScreen> createState() => _AdjustScreenState();
}

class _AdjustScreenState extends State<AdjustScreen> {
  static const _scanner = DocumentScanner();

  Uint8List? _bytes;
  double _aspectRatio = 3 / 4;
  Quad? _quad;
  late ImageFilter _filter = widget.initialFilter;
  bool _preview = false;
  Uint8List? _previewJpeg;
  bool _busy = false;
  int _previewGeneration = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final bytes = await File(widget.photoPath).readAsBytes();
    final image = await _decode(bytes);
    final detected =
        widget.initialQuad ??
        await widget.compute(() => _scanner.detect(bytes));
    if (!mounted) return;
    setState(() {
      _bytes = bytes;
      _aspectRatio = image.width / image.height;
      _quad = detected ?? widget.fallbackQuad ?? Quad.inset(0.05);
    });
    image.dispose();
  }

  static Future<ui.Image> _decode(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 64);
    return (await codec.getNextFrame()).image;
  }

  Future<void> _refreshPreview() async {
    final bytes = _bytes, quad = _quad, filter = _filter;
    if (bytes == null || quad == null) return;
    final generation = ++_previewGeneration;
    final jpeg = await widget.compute(
      () => _scanner.render(bytes, quad, filter, maxSide: 1200),
    );
    if (mounted && generation == _previewGeneration) {
      setState(() => _previewJpeg = jpeg);
    }
  }

  Future<void> _validate() async {
    final bytes = _bytes, quad = _quad, filter = _filter;
    if (bytes == null || quad == null) return;
    setState(() => _busy = true);
    final jpeg = await widget.compute(
      () => _scanner.render(bytes, quad, filter),
    );
    if (!mounted) return;
    Navigator.pop(
      context,
      ScanResult(
        photoPath: widget.photoPath,
        quad: quad,
        filter: filter,
        processedJpeg: jpeg,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ready = _bytes != null && _quad != null;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Ajuster le cadrage'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          if (ready)
            TextButton(
              onPressed: () => setState(() => _quad = Quad.inset(0)),
              child: const Text(
                'Image entière',
                style: TextStyle(color: Colors.white),
              ),
            ),
        ],
      ),
      body: !ready
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                          value: false,
                          icon: Icon(Icons.crop_free),
                          label: Text('Cadrage'),
                        ),
                        ButtonSegment(
                          value: true,
                          icon: Icon(Icons.visibility_outlined),
                          label: Text('Aperçu'),
                        ),
                      ],
                      selected: {_preview},
                      onSelectionChanged: (s) {
                        setState(() => _preview = s.first);
                        if (_preview) _refreshPreview();
                      },
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: _preview
                          ? _PreviewImage(jpeg: _previewJpeg)
                          : _editor(),
                    ),
                  ),
                  _FilterBar(
                    selected: _filter,
                    onSelected: (f) {
                      setState(() => _filter = f);
                      if (_preview) _refreshPreview();
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                            ),
                            onPressed: _busy
                                ? null
                                : () => Navigator.pop(context),
                            icon: const Icon(Icons.replay),
                            label: const Text('Reprendre'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _busy ? null : _validate,
                            icon: _busy
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.check),
                            label: const Text('Valider'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _editor() => CornerEditor(
    imageAspectRatio: _aspectRatio,
    quad: _quad!,
    onChanged: (q) => setState(() => _quad = q),
    child: Semantics(
      label: 'Photo originale du justificatif',
      image: true,
      child: Image.memory(_bytes!, fit: BoxFit.fill, gaplessPlayback: true),
    ),
  );
}

class _PreviewImage extends StatelessWidget {
  const _PreviewImage({required this.jpeg});

  final Uint8List? jpeg;

  @override
  Widget build(BuildContext context) => jpeg == null
      ? const Center(child: CircularProgressIndicator())
      : Semantics(
          label: 'Aperçu du justificatif recadré',
          image: true,
          child: Image.memory(
            jpeg!,
            fit: BoxFit.contain,
            gaplessPlayback: true,
          ),
        );
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.selected, required this.onSelected});

  final ImageFilter selected;
  final ValueChanged<ImageFilter> onSelected;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Row(
      children: [
        for (final f in ImageFilter.values)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(f.label),
              selected: f == selected,
              onSelected: (_) => onSelected(f),
            ),
          ),
      ],
    ),
  );
}

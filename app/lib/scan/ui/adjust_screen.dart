import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../expense/domain/expense.dart';
import '../domain/quad.dart';
import '../domain/rotation.dart';
import 'corner_editor.dart';
import '../data/document_scanner.dart';

/// Résultat d'un scan validé : la photo brute (non modifiée) et ce qu'il faut pour la traiter.
final class ScanResult {
  const ScanResult({
    required this.photoPath,
    required this.quad,
    required this.filter,
    this.rotation = Rotation.none,
    required this.processedJpeg,
  });

  final String photoPath;
  final Quad quad;
  final ImageFilter filter;
  final Rotation rotation;

  /// Image recadrée + filtrée (et pivotée) calculée sur l'appareil.
  final Uint8List processedJpeg;
}

/// Exécute un calcul lourd hors du thread d'interface (remplaçable dans les tests).
typedef Compute = Future<T> Function<T>(T Function() work);

/// Calcul dans un isolate : l'interface reste fluide pendant la détection et le rendu.
Future<T> inIsolate<T>(T Function() work) => Isolate.run(work);

/// Ajustement des coins et choix du filtre, avec aperçu, comme dans une application de scan.
class AdjustScreen extends StatefulWidget {
  const AdjustScreen({
    super.key,
    required this.photoPath,
    this.initialQuad,
    this.fallbackQuad,
    this.initialFilter = ImageFilter.enhance,
    this.initialRotation = Rotation.none,
    this.title = 'Ajuster le cadrage',
    this.onSkip,
    this.compute = inIsolate,
  });

  final String photoPath;

  /// Contour déjà connu (détection en direct ou cadrage précédent) ; sinon détection sur la photo.
  final Quad? initialQuad;

  /// Utilisé si rien n'est détecté sur la photo (ex. contour vu en direct par la caméra).
  final Quad? fallbackQuad;
  final ImageFilter initialFilter;
  final Rotation initialRotation;
  final String title;

  /// Reprise de plusieurs pages : « Passer » remplace « Reprendre », appelle ce rappel puis ferme
  /// l'écran sans résultat.
  final VoidCallback? onSkip;
  final Compute compute;

  @override
  State<AdjustScreen> createState() => _AdjustScreenState();
}

class _AdjustScreenState extends State<AdjustScreen> {
  // Calculs envoyés à un isolate : construits dans des méthodes statiques pour que la fermeture ne
  // capture que ses paramètres, jamais l'état de l'écran (non transmissible entre isolates).
  static Quad? Function() _detectJob(Uint8List bytes) =>
      () => const DocumentScanner().detect(bytes);

  static Uint8List Function() _renderJob(
    Uint8List bytes,
    Quad quad,
    ImageFilter filter,
    Rotation rotation, {
    int maxSide = 2400,
  }) =>
      () => const DocumentScanner().render(
        bytes,
        quad,
        filter,
        rotation: rotation,
        maxSide: maxSide,
      );

  Uint8List? _bytes;
  double _aspectRatio = 3 / 4;
  Quad? _quad;
  late ImageFilter _filter = widget.initialFilter;
  late Rotation _rotation = widget.initialRotation;
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
        widget.initialQuad ?? await widget.compute(_detectJob(bytes));
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
    final bytes = _bytes, quad = _quad, filter = _filter, rotation = _rotation;
    if (bytes == null || quad == null) return;
    final generation = ++_previewGeneration;
    final jpeg = await widget.compute(
      _renderJob(bytes, quad, filter, rotation, maxSide: 1200),
    );
    if (mounted && generation == _previewGeneration) {
      setState(() => _previewJpeg = jpeg);
    }
  }

  Future<void> _validate() async {
    final bytes = _bytes, quad = _quad, filter = _filter, rotation = _rotation;
    if (bytes == null || quad == null) return;
    setState(() => _busy = true);
    final jpeg = await widget.compute(
      _renderJob(bytes, quad, filter, rotation),
    );
    if (!mounted) return;
    Navigator.pop(
      context,
      ScanResult(
        photoPath: widget.photoPath,
        quad: quad,
        filter: filter,
        rotation: rotation,
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
        title: Text(widget.title),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          if (ready)
            IconButton(
              tooltip: 'Pivoter',
              icon: const Icon(Icons.rotate_right),
              onPressed: _rotate,
            ),
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
                            onPressed: _busy ? null : _leave,
                            icon: Icon(
                              widget.onSkip == null
                                  ? Icons.replay
                                  : Icons.skip_next,
                            ),
                            label: Text(
                              widget.onSkip == null ? 'Reprendre' : 'Passer',
                            ),
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

  /// Quart de tour horaire du rendu ; l'aperçu le montre aussitôt.
  void _rotate() {
    setState(() {
      _rotation = _rotation.next();
      _preview = true;
    });
    _refreshPreview();
  }

  void _leave() {
    widget.onSkip?.call();
    Navigator.pop(context);
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

import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../domain/quad.dart';
import '../domain/quad_smoother.dart';
import '../domain/scan_session.dart';
import '../domain/stability.dart';
import 'adjust_screen.dart';
import 'corner_editor.dart';
import 'review_screen.dart';
import '../data/document_scanner.dart';

/// Scan terminé : le mode choisi et les pages validées, rendues sur l'appareil.
final class ScanCompleted {
  const ScanCompleted(this.mode, this.pages);

  final ScanMode mode;
  final List<ScanResult> pages;
}

/// Caméra de scan : contour du document en direct, déclenchement automatique quand le cadrage
/// est stable. En mode Ticket, la prise ouvre la revue ; en mode Document, les pages s'empilent
/// dans le coin jusqu'à ce qu'on touche la pile. Renvoie [ScanCompleted], ou `null` si abandon.
class CameraScreen extends StatefulWidget {
  const CameraScreen({
    super.key,
    this.initialMode = ScanMode.ticket,
    this.modeLocked = false,
    this.compute = inIsolate,
  });

  final ScanMode initialMode;

  /// Mode imposé par l'appelant (ex. ajout de pages à un document) : pas de carrousel.
  final bool modeLocked;
  final Compute compute;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  String? _error;
  Quad? _liveQuad;
  bool _detectionFailed = false;
  late ScanSession _session = ScanSession(widget.initialMode);

  /// Scan terminé ou abandonné : l'écran se ferme, la caméra ne doit plus repartir.
  bool _done = false;
  final _tracker = StabilityTracker();
  final _smoother = QuadSmoother();
  bool _autoCapture = true;
  bool _analyzing = false;
  bool _capturing = false;
  FlashMode _flash = FlashMode.off;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      controller.dispose();
      _controller = null;
    } else if (state == AppLifecycleState.resumed) {
      _start();
    }
  }

  Future<void> _start() async {
    try {
      final cameras = await availableCameras();
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset
            .max, // la photo brute pleine définition est l'original conservé
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      await controller.setFlashMode(_flash);
      await controller.startImageStream(_onFrame);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } on Object catch (e) {
      if (mounted) setState(() => _error = 'Caméra indisponible : $e');
    }
  }

  /// Analyse une image du flux à la fois (les autres sont ignorées) pour rester fluide.
  /// L'image est réduite sur place avant d'être envoyée à l'isolate : copier le plan Y pleine
  /// définition (12 Mo à `ResolutionPreset.max`) à chaque image rendait la détection trop lente.
  void _onFrame(CameraImage frame) {
    if (_analyzing || _capturing) return;
    _analyzing = true;
    final (Uint8List, int, int) sample;
    Uint8List? chroma;
    try {
      final plane = frame.planes.first; // plan Y = luminance
      sample = downsampleLuma(
        plane.bytes,
        width: frame.width,
        height: frame.height,
        bytesPerRow: plane.bytesPerRow,
        maxSide: DocumentScanner.liveMaxSide,
      );
      if (frame.planes.length > 1) {
        // Plan U (Cb) : sert à repérer un papier crème sur une feuille blanche.
        final u = frame.planes[1];
        chroma = sampleChroma(
          u.bytes,
          lumaWidth: frame.width,
          lumaHeight: frame.height,
          bytesPerRow: u.bytesPerRow,
          pixelStride: u.bytesPerPixel ?? 1,
          width: sample.$2,
          height: sample.$3,
        );
      }
    } on Object catch (e, st) {
      _onDetectionError(e, st);
      _analyzing = false;
      return;
    }
    final (small, width, height) = sample;
    final rotation = _controller?.description.sensorOrientation ?? 90;
    detectInBackground(
          small,
          width: width,
          height: height,
          blueChroma: chroma,
          // Contour affiché, ramené dans le repère du capteur.
          tracked: _liveQuad?.rotated(-rotation),
        )
        .then(
          (quad) => _onDetected(quad?.rotated(rotation)),
          onError: _onDetectionError,
        )
        .whenComplete(() => _analyzing = false);
  }

  void _onDetected(Quad? onScreen) {
    if (!mounted) return;
    final now = DateTime.now();
    final fire = _tracker.update(onScreen, now);
    setState(() {
      _liveQuad = _smoother.update(onScreen, now);
      _detectionFailed = false;
    });
    if (fire && _autoCapture) _capture();
  }

  /// La capture manuelle reste possible ; le détail technique ne va que dans les journaux.
  void _onDetectionError(Object e, StackTrace st) {
    debugPrint('Détection en direct impossible : $e\n$st');
    if (!mounted) return;
    _tracker.update(null, DateTime.now());
    if (_detectionFailed && _liveQuad == null) return;
    _smoother.reset();
    setState(() {
      _liveQuad = null;
      _detectionFailed = true;
    });
  }

  /// Nouvelle page ou autre mode : ni le contour affiché ni l'attente ne valent plus.
  void _forgetLiveQuad() {
    _tracker.reset();
    _smoother.reset();
    _liveQuad = null;
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || _capturing) return;
    setState(() => _capturing = true);
    HapticFeedback.mediumImpact();
    try {
      await controller.stopImageStream();
      final photo = await controller.takePicture();
      await _add([CapturedPage(photoPath: photo.path, hint: _liveQuad)]);
    } on CameraException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Échec de la prise : $e')));
      }
    } finally {
      await _resumeStream();
      if (mounted) setState(() => _capturing = false);
    }
  }

  /// Relance la détection en direct, sauf si le scan est terminé (l'écran se ferme).
  Future<void> _resumeStream() async {
    final controller = _controller;
    if (_done || !mounted || controller == null) return;
    if (controller.value.isStreamingImages) return;
    try {
      setState(_forgetLiveQuad);
      await controller.startImageStream(_onFrame);
    } on CameraException catch (e) {
      debugPrint('Reprise de la détection en direct impossible : $e');
    }
  }

  /// Images existantes : une pour un ticket, plusieurs pour un document ; puis la revue.
  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    final photos = _session.mode == ScanMode.document
        ? await picker.pickMultiImage(requestFullMetadata: false)
        : [
            ?await picker.pickImage(
              source: ImageSource.gallery,
              requestFullMetadata: false,
            ),
          ];
    if (photos.isEmpty) return;
    await _add([for (final p in photos) CapturedPage(photoPath: p.path)]);
    // Un ticket est déjà passé en revue par _add ; un document y va maintenant.
    if (_session.mode == ScanMode.document && !_done) await _review();
  }

  /// Ajoute les pages prises ; un ticket part aussitôt en revue, un document s'empile.
  Future<void> _add(List<CapturedPage> pages) async {
    if (!mounted) return;
    var session = _session;
    for (final page in pages) {
      if (!session.canAdd) break;
      session = session.withPage(page);
    }
    setState(() => _session = session);
    HapticFeedback.lightImpact();
    if (_session.mode == ScanMode.ticket) await _review();
  }

  /// Revue des pages prises : enregistrer termine le scan, sinon on revient à la visée.
  Future<void> _review() async {
    final outcome = await Navigator.push<ReviewOutcome>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ReviewScreen(session: _session, compute: widget.compute),
      ),
    );
    if (!mounted) return;
    switch (outcome) {
      case ReviewSaved(:final pages):
        _done = true;
        Navigator.pop(context, ScanCompleted(_session.mode, pages));
      case ReviewContinue(:final session):
        setState(() => _session = session);
      case null:
        break;
    }
  }

  void _setMode(ScanMode mode) => setState(() {
    _session = _session.withMode(mode);
    _forgetLiveQuad();
  });

  /// Pendant la revue, la détection en direct est inutile : on coupe le flux.
  Future<void> _openReview() async {
    final controller = _controller;
    if (controller != null && controller.value.isStreamingImages) {
      await controller.stopImageStream();
    }
    await _review();
    await _resumeStream();
  }

  /// Quitter la caméra avec des pages prises : on confirme avant de les abandonner.
  Future<void> _confirmLeave() async {
    final count = _session.pages.length;
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          count > 1
              ? 'Abandonner les $count pages ?'
              : 'Abandonner la page prise ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Continuer'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Abandonner'),
          ),
        ],
      ),
    );
    if (leave == true && mounted) {
      _done = true;
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    // Vert vif : bien visible sur l'aperçu caméra, quel que soit le fond.
    const color = Colors.greenAccent;
    // Avec des pages prises, revenir en arrière demande confirmation plutôt que de les perdre.
    return PopScope(
      canPop: _session.pages.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: _scaffold(context, controller, color),
    );
  }

  Widget _scaffold(
    BuildContext context,
    CameraController? controller,
    Color color,
  ) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          _session.mode == ScanMode.document
              ? 'Page ${_session.pages.length + 1}'
              : 'Scanner un ticket',
        ),
        actions: [
          IconButton(
            tooltip: _flash == FlashMode.torch
                ? 'Éteindre la lampe'
                : 'Allumer la lampe',
            icon: Icon(
              _flash == FlashMode.torch ? Icons.flash_on : Icons.flash_off,
            ),
            onPressed: controller == null ? null : _toggleFlash,
          ),
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            onPressed: () => setState(() {
              _autoCapture = !_autoCapture;
              _tracker.reset();
            }),
            icon: Icon(
              _autoCapture
                  ? Icons.motion_photos_auto
                  : Icons.motion_photos_off_outlined,
            ),
            label: Text(_autoCapture ? 'Auto' : 'Manuel'),
          ),
        ],
      ),
      body: _error != null
          ? Column(
              children: [
                Expanded(
                  child: _CameraError(
                    message: _error!,
                    onGallery: _pickFromGallery,
                  ),
                ),
                _modeSelector(),
                const SizedBox(height: 24),
              ],
            )
          : controller == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: Center(
                    child: AspectRatio(
                      // L'aperçu est en paysage côté capteur ; l'écran est verrouillé en portrait.
                      aspectRatio: 1 / controller.value.aspectRatio,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CameraPreview(controller),
                          if (_liveQuad != null)
                            LayoutBuilder(
                              builder: (context, c) => CustomPaint(
                                painter: QuadPainter(
                                  _liveQuad!,
                                  Offset.zero & c.biggest,
                                  color: color,
                                  fillProgress: _autoCapture
                                      ? _tracker.progress
                                      : 0,
                                ),
                              ),
                            ),
                          if (_capturing)
                            const ColoredBox(color: Colors.white24),
                        ],
                      ),
                    ),
                  ),
                ),
                _Hint(
                  found: _liveQuad != null,
                  auto: _autoCapture,
                  failed: _detectionFailed,
                  mode: _session.mode,
                ),
                _modeSelector(),
                _ShutterBar(
                  busy: _capturing,
                  onShutter: _capture,
                  onGallery: _pickFromGallery,
                  pages: [for (final p in _session.pages) p.photoPath],
                  onReview: _openReview,
                ),
              ],
            ),
    );
  }

  /// Le mode se choisit avant la première prise, sauf s'il est imposé.
  Widget _modeSelector() => ScanModeSelector(
    mode: _session.mode,
    onChanged: widget.modeLocked || _session.pages.isNotEmpty ? null : _setMode,
  );

  Future<void> _toggleFlash() async {
    final next = _flash == FlashMode.torch ? FlashMode.off : FlashMode.torch;
    await _controller?.setFlashMode(next);
    setState(() => _flash = next);
  }
}

class _Hint extends StatelessWidget {
  const _Hint({
    required this.found,
    required this.auto,
    required this.failed,
    required this.mode,
  });

  final bool found;
  final bool auto;
  final bool failed;
  final ScanMode mode;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: Text(
      failed
          ? 'Détection automatique indisponible — cadrez puis appuyez'
          : !found
          ? mode == ScanMode.ticket
                ? 'Placez le ticket sur un fond contrasté'
                : 'Placez la page sur un fond contrasté'
          : auto
          ? 'Ne bougez plus… capture automatique'
          : 'Document détecté — appuyez pour capturer',
      style: const TextStyle(color: Colors.white),
      textAlign: TextAlign.center,
    ),
  );
}

class _ShutterBar extends StatelessWidget {
  const _ShutterBar({
    required this.busy,
    required this.onShutter,
    required this.onGallery,
    required this.pages,
    required this.onReview,
  });

  final bool busy;
  final VoidCallback onShutter;
  final VoidCallback onGallery;

  /// Photos des pages déjà prises (mode Document).
  final List<String> pages;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            tooltip: 'Choisir une image',
            iconSize: 32,
            color: Colors.white,
            onPressed: busy ? null : onGallery,
            icon: const Icon(Icons.photo_library_outlined),
          ),
          Semantics(
            button: true,
            label: 'Prendre la photo',
            child: GestureDetector(
              onTap: busy ? null : onShutter,
              child: Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 5),
                ),
                padding: const EdgeInsets.all(5),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: busy ? Colors.white38 : Colors.white,
                  ),
                ),
              ),
            ),
          ),
          if (pages.isNotEmpty)
            PageStack(photoPaths: pages, onTap: busy ? () {} : onReview)
          else
            const SizedBox(width: 64),
        ],
      ),
    ),
  );
}

class _CameraError extends StatelessWidget {
  const _CameraError({required this.message, required this.onGallery});

  final String message;
  final VoidCallback onGallery;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.no_photography_outlined,
            color: Colors.white,
            size: 48,
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: const TextStyle(color: Colors.white),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onGallery,
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Choisir une image'),
          ),
        ],
      ),
    ),
  );
}

/// Choix du mode sous la visée : toucher ou glisser. Sans [onChanged], le mode est imposé.
class ScanModeSelector extends StatelessWidget {
  const ScanModeSelector({super.key, required this.mode, this.onChanged});

  final ScanMode mode;
  final ValueChanged<ScanMode>? onChanged;

  @override
  Widget build(BuildContext context) =>
      _ModeCarousel(mode: mode, onChanged: onChanged);
}

class _ModeCarousel extends StatefulWidget {
  const _ModeCarousel({required this.mode, required this.onChanged});

  final ScanMode mode;
  final ValueChanged<ScanMode>? onChanged;

  @override
  State<_ModeCarousel> createState() => _ModeCarouselState();
}

class _ModeCarouselState extends State<_ModeCarousel> {
  double _dragged = 0;

  /// Glisser vers la gauche passe au mode suivant, vers la droite au précédent.
  void _onDragEnd(DragEndDetails _) {
    final onChanged = widget.onChanged;
    final step = _dragged < -40 ? 1 : (_dragged > 40 ? -1 : 0);
    _dragged = 0;
    final next = widget.mode.index + step;
    if (onChanged == null || step == 0) return;
    if (next < 0 || next >= ScanMode.values.length) return;
    onChanged(ScanMode.values[next]);
  }

  @override
  Widget build(BuildContext context) {
    final onChanged = widget.onChanged;
    final modes = onChanged == null ? [widget.mode] : ScanMode.values;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (d) => _dragged += d.delta.dx,
      onHorizontalDragEnd: _onDragEnd,
      child: SizedBox(
        height: 48,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final m in modes)
              _ModeLabel(
                label: m.label,
                selected: m == widget.mode,
                onTap: onChanged == null || m == widget.mode
                    ? null
                    : () => onChanged(m),
              ),
          ],
        ),
      ),
    );
  }
}

class _ModeLabel extends StatelessWidget {
  const _ModeLabel({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: onTap != null,
    selected: selected,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      // Zone de toucher de 48 px de haut ; la pastille visible est plus fine.
      child: SizedBox(
        height: 48,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 36,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.black : Colors.white70,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Pages déjà prises, empilées dans le coin, avec leur nombre ; toucher ouvre la revue.
class PageStack extends StatelessWidget {
  const PageStack({super.key, required this.photoPaths, required this.onTap});

  final List<String> photoPaths;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final count = photoPaths.length;
    final shown = photoPaths.length > 2
        ? photoPaths.sublist(photoPaths.length - 2)
        : photoPaths;
    return Semantics(
      button: true,
      label:
          '$count page${count > 1 ? 's' : ''} prise${count > 1 ? 's' : ''}, revoir',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 72,
          height: 80,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Les feuilles du dessous dépassent un peu, comme une pile de papier.
              for (final (i, path) in shown.indexed)
                Positioned(
                  left: (shown.length - 1 - i) * 6.0,
                  top: (shown.length - 1 - i) * 4.0,
                  child: _Sheet(path: path),
                ),
              Positioned(
                right: 0,
                top: -6,
                child: CircleAvatar(
                  radius: 13,
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  child: Text(
                    '$count',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
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

class _Sheet extends StatelessWidget {
  const _Sheet({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) => Container(
    width: 56,
    height: 72,
    decoration: BoxDecoration(
      color: Colors.white24,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: Colors.white, width: 2),
    ),
    clipBehavior: Clip.antiAlias,
    child: Image.file(
      File(path),
      fit: BoxFit.cover,
      cacheWidth: 160,
      errorBuilder: (_, _, _) => const SizedBox(),
    ),
  );
}

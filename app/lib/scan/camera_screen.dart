import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../domain/quad.dart';
import '../domain/stability.dart';
import 'adjust_screen.dart';
import 'corner_editor.dart';
import 'document_scanner.dart';

/// Caméra de scan : contour du document en direct, déclenchement automatique quand le cadrage
/// est stable, puis écran d'ajustement. Renvoie la liste des [ScanResult] validés (vide si abandon).
/// En mode [multiPage], la caméra reste ouverte après chaque page jusqu'à « Terminer ».
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key, this.multiPage = false});

  final bool multiPage;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  String? _error;
  Quad? _liveQuad;
  bool _detectionFailed = false;
  final _pages = <ScanResult>[];
  final _tracker = StabilityTracker();
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
    detectInBackground(small, width: width, height: height, blueChroma: chroma)
        .then(
          (quad) => _onDetected(quad?.rotated(rotation)),
          onError: _onDetectionError,
        )
        .whenComplete(() => _analyzing = false);
  }

  void _onDetected(Quad? onScreen) {
    if (!mounted) return;
    final fire = _tracker.update(onScreen, DateTime.now());
    setState(() {
      _liveQuad = onScreen;
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
    setState(() {
      _liveQuad = null;
      _detectionFailed = true;
    });
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || _capturing) return;
    setState(() => _capturing = true);
    HapticFeedback.mediumImpact();
    try {
      await controller.stopImageStream();
      final photo = await controller.takePicture();
      await _adjust(photo.path, _liveQuad);
    } on CameraException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Échec de la prise : $e')));
      }
    } finally {
      if (mounted &&
          _controller != null &&
          !_controller!.value.isStreamingImages) {
        _tracker.reset();
        await _controller!.startImageStream(_onFrame);
      }
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _pickFromGallery() async {
    final photo = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      requestFullMetadata: false,
    );
    if (photo != null) await _adjust(photo.path, null);
  }

  /// L'écran d'ajustement redétecte sur la photo pleine définition ; le contour en direct sert de repli.
  Future<void> _adjust(String photoPath, Quad? liveQuad) async {
    if (!mounted) return;
    final result = await Navigator.push<ScanResult>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            AdjustScreen(photoPath: photoPath, fallbackQuad: liveQuad),
      ),
    );
    if (result == null || !mounted) return;
    if (!widget.multiPage) {
      Navigator.pop(context, [result]);
      return;
    }
    setState(() => _pages.add(result));
    HapticFeedback.lightImpact();
  }

  void _finish() => Navigator.pop(context, List.of(_pages));

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final color = Theme.of(context).colorScheme.primaryContainer;
    // En multi-pages, revenir en arrière garde les pages déjà validées.
    return PopScope(
      canPop: _pages.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _finish();
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
          widget.multiPage
              ? 'Page ${_pages.length + 1}'
              : 'Scanner un justificatif',
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
          ? _CameraError(message: _error!, onGallery: _pickFromGallery)
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
                ),
                _ShutterBar(
                  busy: _capturing,
                  onShutter: _capture,
                  onGallery: _pickFromGallery,
                  pages: _pages.length,
                  onFinish: _finish,
                ),
              ],
            ),
    );
  }

  Future<void> _toggleFlash() async {
    final next = _flash == FlashMode.torch ? FlashMode.off : FlashMode.torch;
    await _controller?.setFlashMode(next);
    setState(() => _flash = next);
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.found, required this.auto, required this.failed});

  final bool found;
  final bool auto;
  final bool failed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: Text(
      failed
          ? 'Détection automatique indisponible — cadrez puis appuyez'
          : !found
          ? 'Placez le justificatif sur un fond contrasté'
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
    required this.onFinish,
  });

  final bool busy;
  final VoidCallback onShutter;
  final VoidCallback onGallery;

  /// Pages déjà validées (mode multi-pages).
  final int pages;
  final VoidCallback onFinish;

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
          if (pages > 0)
            FilledButton(
              onPressed: busy ? null : onFinish,
              style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
              child: Text('Terminer ($pages)'),
            )
          else
            const SizedBox(width: 48),
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

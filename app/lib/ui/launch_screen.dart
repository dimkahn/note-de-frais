import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// Affiche la page de chargement pendant [load] (et au moins [minDuration], pour qu'elle ne
/// clignote pas), puis l'application construite avec le résultat — ou l'erreur de démarrage.
class LaunchGate<T> extends StatefulWidget {
  const LaunchGate({
    super.key,
    required this.load,
    required this.builder,
    this.minDuration = const Duration(milliseconds: 1200),
  });

  final Future<T> load;
  final Widget Function(T value) builder;
  final Duration minDuration;

  @override
  State<LaunchGate<T>> createState() => _LaunchGateState<T>();
}

class _LaunchGateState<T> extends State<LaunchGate<T>> {
  late final Future<T> _ready = _waitAtLeast();

  Future<T> _waitAtLeast() async {
    final results = await Future.wait<Object?>([
      widget.load,
      Future<void>.delayed(widget.minDuration),
    ]);
    return results.first as T;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
    future: _ready,
    builder: (context, snapshot) => AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      child: switch (snapshot) {
        AsyncSnapshot(hasError: true, :final error) => LaunchScreen(
          key: const ValueKey('error'),
          error: error,
        ),
        AsyncSnapshot(hasData: true, :final data) => KeyedSubtree(
          key: const ValueKey('app'),
          child: widget.builder(data as T),
        ),
        _ => const LaunchScreen(key: ValueKey('loading')),
      },
    ),
  );
}

/// Page de chargement : le ticket du logo glisse en place sur le bleu encre, puis le nom.
class LaunchScreen extends StatelessWidget {
  const LaunchScreen({super.key, this.error});

  /// Erreur de démarrage à montrer à la place de la progression.
  final Object? error;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.of(context).disableAnimations;
    final text = Theme.of(context).textTheme;
    // Icônes de la barre d'état claires et barre de navigation bleue, le temps du chargement.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: const Color(0xFF1F33B0),
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF3B5BF0), AppTheme.ink, Color(0xFF1F33B0)],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: still ? 1 : 0, end: 1),
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.easeOutCubic,
                  builder: (context, t, child) => Opacity(
                    opacity: t,
                    child: Transform.translate(
                      offset: Offset(0, 24 * (1 - t)),
                      child: child,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ExcludeSemantics(
                        child: Image.asset(
                          'assets/logo/icon_foreground.png',
                          width: 200,
                          height: 200,
                        ),
                      ),
                      Text(
                        'Note de frais',
                        style: text.headlineMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Vos justificatifs, recadrés et lus',
                        textAlign: TextAlign.center,
                        style: text.bodyLarge?.copyWith(
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                      const SizedBox(height: 32),
                      if (error == null)
                        SizedBox(
                          width: 140,
                          child: LinearProgressIndicator(
                            minHeight: 4,
                            borderRadius: BorderRadius.circular(2),
                            color: AppTheme.highlighter,
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.2,
                            ),
                            semanticsLabel: 'Chargement',
                          ),
                        )
                      else
                        Text(
                          'Démarrage impossible : $error',
                          textAlign: TextAlign.center,
                          style: text.bodyMedium?.copyWith(color: Colors.white),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

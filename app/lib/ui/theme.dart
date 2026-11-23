import 'package:flutter/material.dart';

/// Identité visuelle : le bleu d'une encre de stylo bille sur du papier de caisse.
///
/// - Encre (`primary`) #2747D8 : 7,0:1 sur blanc ; #A9B8FF en sombre : 8,9:1 sur #12131A.
/// - Surligneur (`tertiary`) ambre : réservé aux statuts « à vérifier / en attente ».
/// - Montants en chiffres tabulaires gras ; police système pour tout le reste.
abstract final class AppTheme {
  static const ink = Color(0xFF2747D8);
  static const inkDark = Color(0xFFA9B8FF);
  static const highlighter = Color(0xFFF2B705);

  static ThemeData light() => _build(
    ColorScheme.fromSeed(
      seedColor: ink,
      dynamicSchemeVariant: DynamicSchemeVariant.vibrant,
    ).copyWith(
      primary: ink,
      onPrimary: Colors.white,
      surface: const Color(0xFFF7F8FC),
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: Colors.white,
      surfaceContainer: const Color(0xFFEEF0F8),
      tertiary: const Color(0xFF7A5900),
      onTertiary: Colors.white,
      tertiaryContainer: const Color(0xFFFFE08A),
    ),
  );

  static ThemeData dark() => _build(
    ColorScheme.fromSeed(
      seedColor: ink,
      brightness: Brightness.dark,
      dynamicSchemeVariant: DynamicSchemeVariant.vibrant,
    ).copyWith(
      primary: inkDark,
      onPrimary: const Color(0xFF0E1A66),
      surface: const Color(0xFF12131A),
      surfaceContainerLow: const Color(0xFF1B1D26),
      surfaceContainer: const Color(0xFF22242F),
      tertiary: highlighter,
      onTertiary: Colors.black,
    ),
  );

  static ThemeData _build(ColorScheme scheme) {
    final base = ThemeData(colorScheme: scheme, useMaterial3: true);
    final text = base.textTheme;
    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      textTheme: text.copyWith(
        headlineMedium: text.headlineMedium?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
        titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        centerTitle: false,
        // Pas de `titleTextStyle` : il court-circuiterait `foregroundColor` (blanc sur l'écran caméra).
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainer,
        // Champ « filled » Material 3 : le libellé reste dans la zone grisée (une bordure
        // « outline » invisible le faisait flotter à cheval sur le bord). Le trait du bas prend
        // tout seul la couleur de l'état : encre au focus, rouge en erreur.
        border: UnderlineInputBorder(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        indicatorColor: scheme.primary.withValues(alpha: 0.14),
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStatePropertyAll(
          text.labelMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
    );
  }
}

/// Style des montants : chiffres tabulaires, pour que les colonnes s'alignent.
TextStyle? amountStyle(TextStyle? base) => base?.copyWith(
  fontWeight: FontWeight.w700,
  fontFeatures: const [FontFeature.tabularFigures()],
);

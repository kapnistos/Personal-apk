import 'package:flutter/material.dart';

/// Hand-picked palette: warm paper tones with a deep green accent.
class Palette {
  final Color background;
  final Color surface;
  final Color raised;
  final Color ink;
  final Color muted;
  final Color line;
  final Color accent;
  final Color onAccent;
  final Color danger;
  final Color positive;

  const Palette({
    required this.background,
    required this.surface,
    required this.raised,
    required this.ink,
    required this.muted,
    required this.line,
    required this.accent,
    required this.onAccent,
    required this.danger,
    required this.positive,
  });

  static const light = Palette(
    background: Color(0xFFF4F2EC),
    surface: Color(0xFFFFFFFF),
    raised: Color(0xFFEDEAE2),
    ink: Color(0xFF1D1C1A),
    muted: Color(0xFF6F6A60),
    line: Color(0xFFE3DFD5),
    accent: Color(0xFF1F6F54),
    onAccent: Color(0xFFFFFFFF),
    danger: Color(0xFFB4412F),
    positive: Color(0xFF2D7A4B),
  );

  static const dark = Palette(
    background: Color(0xFF111210),
    surface: Color(0xFF1A1B19),
    raised: Color(0xFF242522),
    ink: Color(0xFFECEAE3),
    muted: Color(0xFF9C978C),
    line: Color(0xFF2C2D2A),
    accent: Color(0xFF63C39A),
    onAccent: Color(0xFF0D2219),
    danger: Color(0xFFE07A66),
    positive: Color(0xFF6BC68E),
  );

  static Palette of(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? dark : light;
}

/// Accent colours for each mini-app tile.
class TileColors {
  static const weather = Color(0xFF3A78C9);
  static const mail = Color(0xFFC0563F);
  static const notes = Color(0xFFCF9418);
  static const todo = Color(0xFF1F7A5A);
  static const finance = Color(0xFF6650AE);
  static const claude = Color(0xFFC96442);
}

ThemeData buildTheme(Brightness brightness) {
  final p = brightness == Brightness.dark ? Palette.dark : Palette.light;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: p.accent,
    onPrimary: p.onAccent,
    secondary: p.accent,
    onSecondary: p.onAccent,
    error: p.danger,
    onError: Colors.white,
    surface: p.surface,
    onSurface: p.ink,
    surfaceContainerLowest: p.background,
    surfaceContainerLow: p.surface,
    surfaceContainer: p.surface,
    surfaceContainerHigh: p.raised,
    surfaceContainerHighest: p.raised,
    onSurfaceVariant: p.muted,
    outline: p.line,
    outlineVariant: p.line,
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
    fontFamily: 'Inter',
    scaffoldBackgroundColor: p.background,
    splashFactory: InkSparkle.splashFactory,
    visualDensity: VisualDensity.standard,
  );

  final text = base.textTheme.apply(bodyColor: p.ink, displayColor: p.ink);

  return base.copyWith(
    textTheme: text.copyWith(
      headlineLarge: text.headlineLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.8),
      headlineMedium: text.headlineMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.6),
      headlineSmall: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.4),
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.3),
      titleMedium: text.titleMedium?.copyWith(fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.1),
      titleSmall: text.titleSmall?.copyWith(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 0),
      bodyLarge: text.bodyLarge?.copyWith(fontSize: 16.5, letterSpacing: 0, height: 1.4),
      bodyMedium: text.bodyMedium?.copyWith(fontSize: 15, letterSpacing: 0, height: 1.4),
      bodySmall: text.bodySmall?.copyWith(fontSize: 13, letterSpacing: 0, height: 1.35),
      labelLarge: text.labelLarge?.copyWith(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 0),
      labelMedium: text.labelMedium?.copyWith(fontSize: 13, letterSpacing: 0),
      labelSmall: text.labelSmall?.copyWith(fontSize: 12, letterSpacing: 0.1),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: p.background,
      surfaceTintColor: Colors.transparent,
      foregroundColor: p.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge?.copyWith(fontSize: 21, fontWeight: FontWeight.w600, letterSpacing: -0.3),
    ),
    cardTheme: CardThemeData(
      color: p.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: p.line),
      ),
    ),
    dividerTheme: DividerThemeData(color: p.line, thickness: 1, space: 1),
    listTileTheme: ListTileThemeData(iconColor: p.muted, contentPadding: const EdgeInsets.symmetric(horizontal: 16)),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.raised,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      hintStyle: TextStyle(fontFamily: 'Inter', color: p.muted),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: p.accent, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
        foregroundColor: p.ink,
        side: BorderSide(color: p.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: p.accent,
      foregroundColor: p.onAccent,
      elevation: 0,
      highlightElevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: p.accent.withValues(alpha: 0.14),
      elevation: 0,
      height: 64,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontFamily: 'Inter',
          fontSize: 13,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
          color: s.contains(WidgetState.selected) ? p.ink : p.muted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(color: s.contains(WidgetState.selected) ? p.accent : p.muted),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: p.surface,
      indicatorColor: p.accent.withValues(alpha: 0.14),
      selectedIconTheme: IconThemeData(color: p.accent),
      unselectedIconTheme: IconThemeData(color: p.muted),
      selectedLabelTextStyle: TextStyle(fontFamily: 'Inter', color: p.ink, fontWeight: FontWeight.w600, fontSize: 13),
      unselectedLabelTextStyle: TextStyle(fontFamily: 'Inter', color: p.muted, fontSize: 13),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: p.raised,
      selectedColor: p.accent,
      secondaryLabelStyle: TextStyle(fontFamily: 'Inter', color: p.onAccent, fontWeight: FontWeight.w600),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      labelStyle: TextStyle(
        fontFamily: 'Inter',
        fontWeight: FontWeight.w500,
        color: WidgetStateColor.resolveWith((s) => s.contains(WidgetState.selected) ? p.onAccent : p.ink),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: p.ink,
      contentTextStyle: TextStyle(fontFamily: 'Inter', color: p.background),
      actionTextColor: brightness == Brightness.dark ? Palette.light.accent : Palette.dark.accent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: p.line),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      side: BorderSide(color: p.muted, width: 1.5),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
      },
    ),
  );
}

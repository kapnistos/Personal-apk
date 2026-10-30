import 'package:flutter/material.dart';

/// Palette: near-black (or cool grey) ground, flat cards, one confident blue.
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
    background: Color(0xFFF1F2F6),
    surface: Color(0xFFFFFFFF),
    raised: Color(0xFFE8E9EE),
    ink: Color(0xFF0B0C0E),
    muted: Color(0xFF6B6F78),
    line: Color(0xFFE4E5EA),
    accent: Color(0xFF1E5BF0),
    onAccent: Color(0xFFFFFFFF),
    danger: Color(0xFFD8352F),
    positive: Color(0xFF128A4E),
  );

  static const dark = Palette(
    background: Color(0xFF000000),
    surface: Color(0xFF16171A),
    raised: Color(0xFF232428),
    ink: Color(0xFFFFFFFF),
    muted: Color(0xFF8D9099),
    line: Color(0xFF232428),
    accent: Color(0xFF4F86FF),
    onAccent: Color(0xFFFFFFFF),
    danger: Color(0xFFFF5D57),
    positive: Color(0xFF3DD68C),
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
      displaySmall: text.displaySmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -1.2),
      headlineLarge: text.headlineLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1.0),
      headlineMedium: text.headlineMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.8),
      headlineSmall: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.5),
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.4),
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
      titleTextStyle: text.titleLarge?.copyWith(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.6),
    ),
    cardTheme: CardThemeData(
      color: p.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    // Tabs are a row of pills; the chosen one is solid.
    tabBarTheme: TabBarThemeData(
      dividerColor: Colors.transparent,
      indicatorSize: TabBarIndicatorSize.tab,
      indicator: ShapeDecoration(color: p.raised, shape: const StadiumBorder()),
      labelColor: p.ink,
      unselectedLabelColor: p.muted,
      labelStyle: const TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w600),
      unselectedLabelStyle: const TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w500),
      overlayColor: WidgetStateProperty.all(Colors.transparent),
      splashFactory: NoSplash.splashFactory,
    ),
    dividerTheme: DividerThemeData(color: p.line, thickness: 0.6, space: 1),
    listTileTheme: ListTileThemeData(iconColor: p.muted, contentPadding: const EdgeInsets.symmetric(horizontal: 16)),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.raised,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      hintStyle: TextStyle(fontFamily: 'Inter', color: p.muted),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: p.accent, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 22),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 15.5, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        foregroundColor: p.ink,
        backgroundColor: p.raised,
        side: BorderSide.none,
        shape: const StadiumBorder(),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: p.accent,
      foregroundColor: p.onAccent,
      elevation: 0,
      highlightElevation: 0,
      shape: const StadiumBorder(),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.background,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Colors.transparent,
      elevation: 0,
      height: 66,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontFamily: 'Inter',
          fontSize: 13,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
          color: s.contains(WidgetState.selected) ? p.ink : p.muted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(color: s.contains(WidgetState.selected) ? p.ink : p.muted, size: 25),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: p.surface,
      indicatorColor: p.raised,
      selectedIconTheme: IconThemeData(color: p.ink),
      unselectedIconTheme: IconThemeData(color: p.muted),
      selectedLabelTextStyle: TextStyle(fontFamily: 'Inter', color: p.ink, fontWeight: FontWeight.w600, fontSize: 13),
      unselectedLabelTextStyle: TextStyle(fontFamily: 'Inter', color: p.muted, fontSize: 13),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: p.raised,
      selectedColor: p.ink,
      checkmarkColor: p.background,
      secondaryLabelStyle: TextStyle(fontFamily: 'Inter', color: p.background, fontWeight: FontWeight.w600),
      side: BorderSide.none,
      shape: const StadiumBorder(),
      showCheckmark: false,
      labelStyle: TextStyle(
        fontFamily: 'Inter',
        fontWeight: FontWeight.w600,
        color: WidgetStateColor.resolveWith((s) => s.contains(WidgetState.selected) ? p.background : p.ink),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: p.ink,
      contentTextStyle: TextStyle(fontFamily: 'Inter', color: p.background),
      actionTextColor: brightness == Brightness.dark ? Palette.light.accent : Palette.dark.accent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: const CircleBorder(),
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

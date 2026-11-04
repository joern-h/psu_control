import 'package:flutter/material.dart';

/// Chart colors, validated for both surfaces (see dataviz reference palette).
class ChartPalette {
  const ChartPalette({
    required this.voltage,
    required this.current,
    required this.surface,
    required this.grid,
    required this.axis,
    required this.muted,
    required this.ink,
  });

  factory ChartPalette.of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;

  static const light = ChartPalette(
    voltage: Color(0xFF2A78D6),
    current: Color(0xFFEB6834),
    surface: Color(0xFFFCFCFB),
    grid: Color(0xFFE1E0D9),
    axis: Color(0xFFC3C2B7),
    muted: Color(0xFF898781),
    ink: Color(0xFF0B0B0B),
  );

  static const dark = ChartPalette(
    voltage: Color(0xFF3987E5),
    current: Color(0xFFD95926),
    surface: Color(0xFF1A1A19),
    grid: Color(0xFF2C2C2A),
    axis: Color(0xFF383835),
    muted: Color(0xFF898781),
    ink: Color(0xFFF0EFEC),
  );

  final Color voltage;
  final Color current;
  final Color surface;
  final Color grid;
  final Color axis;
  final Color muted;
  final Color ink;
}

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF2A78D6),
    brightness: brightness,
    surface: dark ? const Color(0xFF0D0D0D) : const Color(0xFFF9F9F7),
  );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    visualDensity: VisualDensity.comfortable,
    cardTheme: CardThemeData(
      elevation: 0,
      color: dark ? const Color(0xFF1A1A19) : const Color(0xFFFCFCFB),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: dark ? Colors.white10 : Colors.black12),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      isDense: true,
    ),
  );
}

/// Tabular figures so live numbers do not jitter horizontally.
const tabularFigures = [FontFeature.tabularFigures()];

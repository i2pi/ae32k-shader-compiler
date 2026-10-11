// The look of scion_controller_app (its main.dart, grid.dart, labeled_card.dart, app_button.dart):
// dark neutral surfaces, D-DIN for the UI, the app's accents.
import 'package:ae32k_shader_compiler/ae32k_shader_compiler.dart'
    show TokenKind;
import 'package:flutter/material.dart';

class Sc {
  static const background = Color(0xFF1C1C1E);
  static const surface = Color(0xFF2C2C2E);
  static const panel = Color(0xFF2A2A2C);
  static const card = Color(0xFF323236);
  static const inset = Color(0xFF29292D);
  static const buttonFace = Color(0xFF34343A);
  static const buttonHover = Color(0xFF3B3B42);
  static const primary = Color(0xFFFFF176);
  static const blue = Color(0xFF6A9ACA);
  static const gold = Color(0xFFC9B066);
  static const amber = Color(0xFFF0B830);
  static const red = Color(0xFFFF6B6B);
  static const green = Color(0xFF7FC48A);
  static const text = Color(0xFFF1F1F3);
  static const label = Color(0xFFD2D2D4);
  static const body = Color(0xFFC8C8CE);
  static const caption = Color(0xFFACACB2);
  static const faint = Color(0xFF74747C);

  static const ui = 'DINPro';
  static const mono = 'Menlo';
  static const monoFallback = [
    'SF Mono',
    'Consolas',
    'DejaVu Sans Mono',
    'Liberation Mono',
    'monospace'
  ];

  static TextStyle caps(double size,
          {Color color = caption, FontWeight weight = FontWeight.w400}) =>
      TextStyle(
          fontFamily: ui,
          fontSize: size,
          color: color,
          fontWeight: weight,
          letterSpacing: 0.09 * size,
          fontFeatures: const [FontFeature.tabularFigures()]);

  static TextStyle uiText(double size,
          {Color color = body, FontWeight weight = FontWeight.w400}) =>
      TextStyle(
          fontFamily: ui,
          fontSize: size,
          color: color,
          fontWeight: weight,
          letterSpacing: 0.021 * size + 0.05,
          fontFeatures: const [FontFeature.tabularFigures()]);

  static ThemeData theme() => ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        fontFamily: ui,
        scaffoldBackgroundColor: background,
        colorScheme: ColorScheme.dark(
          primary: primary,
          secondary: Colors.grey[400]!,
          surface: surface,
          onPrimary: Colors.black,
          onSurface: Colors.white,
        ),
        tooltipTheme: TooltipThemeData(
          decoration: BoxDecoration(
            color: const Color(0xFF2E2F34),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.28),
                  blurRadius: 12,
                  offset: const Offset(0, 4))
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          waitDuration: const Duration(milliseconds: 450),
          textStyle: const TextStyle(
              fontFamily: ui,
              fontSize: 12,
              color: Color(0xFFF1F1F3),
              letterSpacing: 0.08),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: Colors.grey[400]!),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            foregroundColor: Colors.grey[300],
            textStyle: const TextStyle(fontFamily: ui, fontSize: 14),
          ),
        ),
        sliderTheme: const SliderThemeData(
          trackHeight: 2,
          activeTrackColor: gold,
          inactiveTrackColor: Color(0xFF45454B),
          thumbColor: Color(0xFFE6E6EA),
          overlayShape: RoundSliderOverlayShape(overlayRadius: 12),
          thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
        ),
      );

  /// Syntax colours.
  static Color token(TokenKind k) => switch (k) {
        TokenKind.comment => faint,
        TokenKind.number || TokenKind.constant => const Color(0xFFE6A07A),
        TokenKind.keyword => gold,
        TokenKind.input => const Color(0xFF83A6C9),
        TokenKind.output => primary,
        TokenKind.function => const Color(0xFF8FD1C1),
        TokenKind.local => const Color(0xFFE6E6EA),
        TokenKind.op => caption,
        TokenKind.directive => amber,
        TokenKind.register => const Color(0xFF83A6C9),
        TokenKind.mode => gold,
        TokenKind.unknown => red,
      };

  /// A card as in scion_controller_app: a lit gradient over the base colour, radius 8.
  static BoxDecoration cardBox([Color base = card]) => BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(base, Colors.white, 0.035 * 0.45)!,
            base,
            Color.lerp(base, Colors.black, 0.035 * 0.35)!
          ],
          stops: const [0, 0.55, 1],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 8,
              offset: const Offset(0, 3))
        ],
      );
}

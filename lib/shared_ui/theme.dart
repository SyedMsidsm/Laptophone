import 'package:material_ui/material_ui.dart';

import 'tokens.dart';

/// Which app a theme is for.
enum AppDevice { phone, laptop }

/// Archivo Expanded, heavy: headings and big numbers only.
TextStyle archivoStyle(double size, double height) => TextStyle(
  fontFamily: 'Archivo',
  fontSize: size,
  height: height / size,
  fontWeight: FontWeight.w800,
  fontVariations: const [
    FontVariation('wght', 800),
    FontVariation('wdth', 125),
  ],
);

/// Roboto Mono for sizes, speeds, addresses and codes.
TextStyle monoStyle(double size, {FontWeight weight = FontWeight.w400}) =>
    TextStyle(
      fontFamily: 'RobotoMono',
      fontSize: size,
      fontWeight: weight,
      fontVariations: [FontVariation('wght', weight.value.toDouble())],
    );

/// The phone theme (Material 3, Roboto) or the laptop theme (Windows 11
/// look, Segoe UI Variable) for the given [brightness].
ThemeData buildTheme(AppDevice device, Brightness brightness) =>
    device == AppDevice.phone
    ? _phoneTheme(brightness)
    : _laptopTheme(brightness);

ColorScheme _scheme({
  required Brightness b,
  required Color primary,
  required Color onPrimary,
  required Color container,
  required Color onContainer,
  required Color other,
  required Color onOther,
}) => ColorScheme(
  brightness: b,
  primary: primary,
  onPrimary: onPrimary,
  primaryContainer: container,
  onPrimaryContainer: onContainer,
  secondary: primary,
  onSecondary: onPrimary,
  secondaryContainer: container,
  onSecondaryContainer: onContainer,
  tertiary: other,
  onTertiary: onOther,
  error: Tokens.danger.of(b),
  onError: Tokens.onDanger.of(b),
  errorContainer: Tokens.dangerSoft.of(b),
  onErrorContainer: Tokens.danger.of(b),
  surface: Tokens.surface.of(b),
  onSurface: Tokens.ink.of(b),
  onSurfaceVariant: Tokens.ink2.of(b),
  surfaceContainerHighest: Tokens.surface2.of(b),
  outline: Tokens.ink2.of(b),
  outlineVariant: Tokens.line.of(b),
);

TextTheme _textTheme({
  required double display,
  required double displayLine,
  required double section,
  required double sectionLine,
  required String? bodyFont,
  required double body,
  required double bodyLine,
  required double caption,
  required double captionLine,
  required double button,
  required FontWeight buttonWeight,
  required Color ink,
}) {
  TextStyle plain(double size, double line, [FontWeight? w]) => TextStyle(
    fontFamily: bodyFont,
    fontFamilyFallback: bodyFont == null ? null : const ['Segoe UI'],
    fontSize: size,
    height: line / size,
    fontWeight: w ?? FontWeight.w400,
    color: ink,
  );
  return TextTheme(
    displayLarge: archivoStyle(40, 44).copyWith(color: ink),
    displayMedium: archivoStyle(display, displayLine).copyWith(color: ink),
    displaySmall: archivoStyle(22, 28).copyWith(color: ink),
    headlineLarge: archivoStyle(display, displayLine).copyWith(color: ink),
    headlineMedium: archivoStyle(24, 30).copyWith(color: ink),
    headlineSmall: archivoStyle(22, 28).copyWith(color: ink),
    titleLarge: archivoStyle(section, sectionLine).copyWith(color: ink),
    titleMedium: plain(body, bodyLine, FontWeight.w600),
    titleSmall: plain(caption, captionLine, FontWeight.w600),
    bodyLarge: plain(body, bodyLine),
    bodyMedium: plain(body, bodyLine),
    bodySmall: plain(caption, captionLine),
    labelLarge: plain(button, bodyLine, buttonWeight),
    labelMedium: plain(caption, captionLine, FontWeight.w600),
    labelSmall: plain(caption, captionLine),
  );
}

ThemeData _phoneTheme(Brightness b) {
  final colors = DeviceColors.of(b);
  final scheme = _scheme(
    b: b,
    primary: colors.phone,
    onPrimary: colors.onPhone,
    container: colors.phoneSoft,
    onContainer: colors.onPhoneSoft,
    other: colors.laptop,
    onOther: colors.onLaptop,
  );
  final text = _textTheme(
    display: 30,
    displayLine: 36,
    section: 18,
    sectionLine: 24,
    bodyFont: null, // The system font (Roboto on Android).
    body: 16,
    bodyLine: 22,
    caption: 13,
    captionLine: 18,
    button: 17,
    buttonWeight: FontWeight.w700,
    ink: scheme.onSurface,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: scheme,
    scaffoldBackgroundColor: Tokens.background.of(b),
    textTheme: text,
    extensions: [colors],
    appBarTheme: AppBarTheme(
      backgroundColor: colors.phoneBand,
      foregroundColor: colors.onBand,
      titleTextStyle: archivoStyle(22, 28).copyWith(color: colors.onBand),
    ),
    cardTheme: CardThemeData(
      color: scheme.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(60),
        shape: const StadiumBorder(),
        textStyle: text.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: const StadiumBorder(),
        textStyle: text.labelLarge,
      ),
    ),
  );
}

ThemeData _laptopTheme(Brightness b) {
  final colors = DeviceColors.of(b);
  final scheme = _scheme(
    b: b,
    primary: colors.laptop,
    onPrimary: colors.onLaptop,
    container: colors.laptopSoft,
    onContainer: colors.onLaptopSoft,
    other: colors.phone,
    onOther: colors.onPhone,
  );
  final text = _textTheme(
    display: 24,
    displayLine: 30,
    section: 15,
    sectionLine: 20,
    bodyFont: 'Segoe UI Variable',
    body: 14,
    bodyLine: 20,
    caption: 12,
    captionLine: 16,
    button: 14,
    buttonWeight: FontWeight.w600,
    ink: scheme.onSurface,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: scheme,
    scaffoldBackgroundColor: Tokens.background.of(b),
    textTheme: text,
    extensions: [colors],
    visualDensity: VisualDensity.compact,
    appBarTheme: AppBarTheme(
      backgroundColor: colors.laptopBand,
      foregroundColor: colors.onBand,
      titleTextStyle: archivoStyle(15, 20).copyWith(color: colors.onBand),
    ),
    cardTheme: CardThemeData(
      color: scheme.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        textStyle: text.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        textStyle: text.labelLarge,
      ),
    ),
  );
}

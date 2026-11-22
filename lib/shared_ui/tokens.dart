import 'package:material_ui/material_ui.dart';

/// Colour tokens from design/DESIGN.md. Each device owns a colour: the phone
/// is orange and the laptop is blue, in both apps.
abstract final class Tokens {
  // Shared neutrals: (light, dark).
  static const background = _Pair(Color(0xFFF5F6F8), Color(0xFF0E1014));
  static const surface = _Pair(Color(0xFFFFFFFF), Color(0xFF171A1F));
  static const surface2 = _Pair(Color(0xFFEDEFF2), Color(0xFF20242B));
  static const line = _Pair(Color(0xFFD5D9E0), Color(0xFF2F343D));
  static const ink = _Pair(Color(0xFF15171C), Color(0xFFECEEF2));
  static const ink2 = _Pair(Color(0xFF575E6B), Color(0xFFA2A9B6));

  // Phone (orange).
  static const phone = _Pair(Color(0xFFC2410C), Color(0xFFFF8F57));
  static const phoneBand = _Pair(Color(0xFFC2410C), Color(0xFF7C2D12));
  static const phoneSoft = _Pair(Color(0xFFFFE7D6), Color(0xFF3B2015));
  static const onPhone = _Pair(Color(0xFFFFFFFF), Color(0xFF1B0B02));
  static const onPhoneSoft = _Pair(Color(0xFF7C2D12), Color(0xFFFFC3A1));

  // Laptop (blue).
  static const laptop = _Pair(Color(0xFF1D4ED8), Color(0xFF8AB0FF));
  static const laptopBand = _Pair(Color(0xFF1D4ED8), Color(0xFF1E3A8A));
  static const laptopSoft = _Pair(Color(0xFFE1E9FF), Color(0xFF172554));
  static const onLaptop = _Pair(Color(0xFFFFFFFF), Color(0xFF0A1530));
  static const onLaptopSoft = _Pair(Color(0xFF1E3A8A), Color(0xFFC7D7FF));
  static const onLaptopBandSecondary = _Pair(
    Color(0xFFE1E9FF),
    Color(0xFFC7D7FF),
  );

  // Danger: failures and Unpair only, always with an icon or a word.
  static const danger = _Pair(Color(0xFFBE123C), Color(0xFFFF7A93));
  static const dangerSoft = _Pair(Color(0xFFFFE4EA), Color(0xFF3A1520));
  static const onDanger = _Pair(Color(0xFFFFFFFF), Color(0xFF2A0510));

  /// Text on a coloured top band.
  static const onBand = Color(0xFFFFFFFF);
}

/// A light value and its dark twin.
class _Pair {
  const _Pair(this.light, this.dark);
  final Color light;
  final Color dark;

  Color of(Brightness b) => b == Brightness.dark ? dark : light;
}

/// Both devices' colours, for badges, tiles and the connection line.
/// Shared by both apps through the theme.
@immutable
class DeviceColors extends ThemeExtension<DeviceColors> {
  const DeviceColors({
    required this.phone,
    required this.phoneBand,
    required this.phoneSoft,
    required this.onPhone,
    required this.onPhoneSoft,
    required this.laptop,
    required this.laptopBand,
    required this.laptopSoft,
    required this.onLaptop,
    required this.onLaptopSoft,
    required this.onBand,
    required this.onLaptopBandSecondary,
    required this.dangerSoft,
    required this.surface2,
    required this.line,
  });

  factory DeviceColors.of(Brightness b) => DeviceColors(
    phone: Tokens.phone.of(b),
    phoneBand: Tokens.phoneBand.of(b),
    phoneSoft: Tokens.phoneSoft.of(b),
    onPhone: Tokens.onPhone.of(b),
    onPhoneSoft: Tokens.onPhoneSoft.of(b),
    laptop: Tokens.laptop.of(b),
    laptopBand: Tokens.laptopBand.of(b),
    laptopSoft: Tokens.laptopSoft.of(b),
    onLaptop: Tokens.onLaptop.of(b),
    onLaptopSoft: Tokens.onLaptopSoft.of(b),
    onBand: Tokens.onBand,
    onLaptopBandSecondary: Tokens.onLaptopBandSecondary.of(b),
    dangerSoft: Tokens.dangerSoft.of(b),
    surface2: Tokens.surface2.of(b),
    line: Tokens.line.of(b),
  );

  final Color phone;
  final Color phoneBand;
  final Color phoneSoft;
  final Color onPhone;
  final Color onPhoneSoft;
  final Color laptop;
  final Color laptopBand;
  final Color laptopSoft;
  final Color onLaptop;
  final Color onLaptopSoft;
  final Color onBand;
  final Color onLaptopBandSecondary;
  final Color dangerSoft;
  final Color surface2;
  final Color line;

  @override
  DeviceColors copyWith({
    Color? phone,
    Color? phoneBand,
    Color? phoneSoft,
    Color? onPhone,
    Color? onPhoneSoft,
    Color? laptop,
    Color? laptopBand,
    Color? laptopSoft,
    Color? onLaptop,
    Color? onLaptopSoft,
    Color? onBand,
    Color? onLaptopBandSecondary,
    Color? dangerSoft,
    Color? surface2,
    Color? line,
  }) => DeviceColors(
    phone: phone ?? this.phone,
    phoneBand: phoneBand ?? this.phoneBand,
    phoneSoft: phoneSoft ?? this.phoneSoft,
    onPhone: onPhone ?? this.onPhone,
    onPhoneSoft: onPhoneSoft ?? this.onPhoneSoft,
    laptop: laptop ?? this.laptop,
    laptopBand: laptopBand ?? this.laptopBand,
    laptopSoft: laptopSoft ?? this.laptopSoft,
    onLaptop: onLaptop ?? this.onLaptop,
    onLaptopSoft: onLaptopSoft ?? this.onLaptopSoft,
    onBand: onBand ?? this.onBand,
    onLaptopBandSecondary: onLaptopBandSecondary ?? this.onLaptopBandSecondary,
    dangerSoft: dangerSoft ?? this.dangerSoft,
    surface2: surface2 ?? this.surface2,
    line: line ?? this.line,
  );

  @override
  DeviceColors lerp(ThemeExtension<DeviceColors>? other, double t) {
    if (other is! DeviceColors) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return DeviceColors(
      phone: mix(phone, other.phone),
      phoneBand: mix(phoneBand, other.phoneBand),
      phoneSoft: mix(phoneSoft, other.phoneSoft),
      onPhone: mix(onPhone, other.onPhone),
      onPhoneSoft: mix(onPhoneSoft, other.onPhoneSoft),
      laptop: mix(laptop, other.laptop),
      laptopBand: mix(laptopBand, other.laptopBand),
      laptopSoft: mix(laptopSoft, other.laptopSoft),
      onLaptop: mix(onLaptop, other.onLaptop),
      onLaptopSoft: mix(onLaptopSoft, other.onLaptopSoft),
      onBand: mix(onBand, other.onBand),
      onLaptopBandSecondary: mix(
        onLaptopBandSecondary,
        other.onLaptopBandSecondary,
      ),
      dangerSoft: mix(dangerSoft, other.dangerSoft),
      surface2: mix(surface2, other.surface2),
      line: mix(line, other.line),
    );
  }
}

/// WCAG contrast ratio between two colours (1 to 21).
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

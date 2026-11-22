import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:personal_sender/shared_ui/theme.dart';
import 'package:personal_sender/shared_ui/tokens.dart';

void main() {
  group('themes build and render in every combination', () {
    for (final device in AppDevice.values) {
      for (final brightness in Brightness.values) {
        testWidgets('${device.name} ${brightness.name}', (tester) async {
          final theme = buildTheme(device, brightness);
          expect(theme.extension<DeviceColors>(), isNotNull);

          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: Scaffold(
                appBar: AppBar(title: const Text('PersonalSender')),
                body: Column(
                  children: [
                    const Text('Connected'),
                    FilledButton(onPressed: () {}, child: const Text('Send')),
                    OutlinedButton(onPressed: () {}, child: const Text('Pair')),
                    Text('192.168.1.6:47820', style: monoStyle(12)),
                    Builder(
                      builder: (context) => Text(
                        'Today',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    Switch(value: true, onChanged: (_) {}),
                    const Card(child: Text('card')),
                  ],
                ),
              ),
            ),
          );
          expect(tester.takeException(), isNull);
          expect(find.text('Connected'), findsOneWidget);
        });
      }
    }
  });

  group('contrast pairs from DESIGN.md are at least 4.5 : 1', () {
    void check(String name, Color fg, Color bg) {
      final ratio = contrastRatio(fg, bg);
      expect(
        ratio,
        greaterThanOrEqualTo(4.5),
        reason: '$name is only ${ratio.toStringAsFixed(2)} : 1',
      );
    }

    for (final b in Brightness.values) {
      final tag = b.name;
      test('shared text ($tag)', () {
        check('ink on background', Tokens.ink.of(b), Tokens.background.of(b));
        check('ink on surface', Tokens.ink.of(b), Tokens.surface.of(b));
        check('ink2 on surface', Tokens.ink2.of(b), Tokens.surface.of(b));
        check('danger on surface', Tokens.danger.of(b), Tokens.surface.of(b));
        check(
          'danger on dangerSoft',
          Tokens.danger.of(b),
          Tokens.dangerSoft.of(b),
        );
      });

      test('phone pairs ($tag)', () {
        check('onPhone on phone', Tokens.onPhone.of(b), Tokens.phone.of(b));
        check('white on phoneBand', Tokens.onBand, Tokens.phoneBand.of(b));
        check(
          'onPhoneSoft on phoneSoft',
          Tokens.onPhoneSoft.of(b),
          Tokens.phoneSoft.of(b),
        );
      });

      test('laptop pairs ($tag)', () {
        check('onLaptop on laptop', Tokens.onLaptop.of(b), Tokens.laptop.of(b));
        check('white on laptopBand', Tokens.onBand, Tokens.laptopBand.of(b));
        check(
          'secondary on laptopBand',
          Tokens.onLaptopBandSecondary.of(b),
          Tokens.laptopBand.of(b),
        );
        check(
          'onLaptopSoft on laptopSoft',
          Tokens.onLaptopSoft.of(b),
          Tokens.laptopSoft.of(b),
        );
      });

      test('the built colour schemes keep their pairs readable ($tag)', () {
        for (final device in AppDevice.values) {
          final s = buildTheme(device, b).colorScheme;
          check('${device.name} onPrimary', s.onPrimary, s.primary);
          check(
            '${device.name} onPrimaryContainer',
            s.onPrimaryContainer,
            s.primaryContainer,
          );
          check('${device.name} onSurface', s.onSurface, s.surface);
          check(
            '${device.name} onSurfaceVariant',
            s.onSurfaceVariant,
            s.surface,
          );
          check('${device.name} onError', s.onError, s.error);
        }
      });
    }

    test('the documented ratios match (spot checks)', () {
      // DESIGN.md: white on the phone orange is 5.2 : 1, on the laptop blue 6.7 : 1.
      expect(
        contrastRatio(Tokens.onPhone.light, Tokens.phone.light),
        closeTo(5.2, 0.1),
      );
      expect(
        contrastRatio(Tokens.onLaptop.light, Tokens.laptop.light),
        closeTo(6.7, 0.1),
      );
      // Orange on its soft tile fails, as DESIGN.md warns.
      expect(
        contrastRatio(Tokens.phone.light, Tokens.phoneSoft.light),
        lessThan(4.5),
      );
    });
  });

  group('fonts are bundled, never fetched', () {
    test('the files exist and pubspec has no font-fetching package', () {
      expect(File('assets/fonts/Archivo.ttf').existsSync(), isTrue);
      expect(File('assets/fonts/RobotoMono.ttf').existsSync(), isTrue);
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, isNot(contains('google_fonts')));
      expect(pubspec, contains('assets/fonts/Archivo.ttf'));
      expect(pubspec, contains('assets/fonts/RobotoMono.ttf'));
    });

    test('no source file fetches fonts at runtime', () {
      final offenders = [
        for (final f in Directory('lib').listSync(recursive: true))
          if (f is File &&
              f.path.endsWith('.dart') &&
              f.readAsStringSync().contains('google_fonts'))
            f.path,
      ];
      expect(offenders, isEmpty);
    });

    test('headings use Archivo at width 125, data uses Roboto Mono', () {
      final h = archivoStyle(30, 36);
      expect(h.fontFamily, 'Archivo');
      expect(h.fontVariations, contains(const FontVariation('wdth', 125)));
      expect(monoStyle(12).fontFamily, 'RobotoMono');
    });
  });
}

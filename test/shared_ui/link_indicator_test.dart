import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:personal_sender/core/discovery/discovery.dart' show NetworkKind;
import 'package:personal_sender/shared_ui/link_indicator.dart';
import 'package:personal_sender/shared_ui/theme.dart';

Widget _host(
  LinkIndicator child, {
  AppDevice device = AppDevice.phone,
  Brightness brightness = Brightness.light,
  bool disableAnimations = false,
}) {
  final theme = buildTheme(device, brightness);
  return MaterialApp(
    theme: theme,
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Scaffold(
        body: Center(
          child: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
    ),
  );
}

void main() {
  group('status sentence', () {
    test('connected names the network kind, never its name', () {
      expect(
        linkStatusSentence(
          state: LinkState.connected,
          network: NetworkKind.wifi,
          peer: AppDevice.laptop,
        ),
        'Connected to your laptop over wi-fi',
      );
      expect(
        linkStatusSentence(
          state: LinkState.connected,
          network: NetworkKind.phoneHotspot,
          peer: AppDevice.laptop,
        ),
        'Connected to your laptop over phone hotspot',
      );
      expect(
        linkStatusSentence(
          state: LinkState.connected,
          network: NetworkKind.laptopHotspot,
          peer: AppDevice.phone,
        ),
        'Connected to your phone over laptop hotspot',
      );
      expect(
        linkStatusSentence(
          state: LinkState.connected,
          network: NetworkKind.unknown,
          peer: AppDevice.phone,
        ),
        'Connected to your phone',
      );
    });

    test('looking and offline', () {
      expect(
        linkStatusSentence(
          state: LinkState.looking,
          network: NetworkKind.wifi,
          peer: AppDevice.laptop,
        ),
        'Looking for your laptop',
      );
      expect(
        linkStatusSentence(
          state: LinkState.offline,
          network: NetworkKind.unknown,
          peer: AppDevice.phone,
        ),
        'Your phone is not reachable',
      );
    });
  });

  group('each state renders with the right semantics label', () {
    final cases = <(LinkState, NetworkKind, String)>[
      (
        LinkState.connected,
        NetworkKind.wifi,
        'Connected to your laptop over wi-fi',
      ),
      (LinkState.looking, NetworkKind.wifi, 'Looking for your laptop'),
      (LinkState.offline, NetworkKind.unknown, 'Your laptop is not reachable'),
    ];
    for (final (state, network, sentence) in cases) {
      testWidgets(state.name, (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          _host(
            LinkIndicator(
              state: state,
              network: network,
              peer: AppDevice.laptop,
            ),
            disableAnimations: true,
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.bySemanticsLabel(sentence), findsOneWidget);
        handle.dispose();
      });
    }
  });

  group('the network chip', () {
    testWidgets('shows the kind while connected or looking', (tester) async {
      await tester.pumpWidget(
        _host(
          const LinkIndicator(
            state: LinkState.connected,
            network: NetworkKind.phoneHotspot,
            peer: AppDevice.laptop,
          ),
        ),
      );
      expect(find.text('Phone hotspot'), findsOneWidget);
    });

    testWidgets('is hidden when offline or the kind is unknown', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const LinkIndicator(
            state: LinkState.offline,
            network: NetworkKind.wifi,
            peer: AppDevice.laptop,
          ),
        ),
      );
      expect(find.text('Wi-Fi'), findsNothing);

      await tester.pumpWidget(
        _host(
          const LinkIndicator(
            state: LinkState.connected,
            network: NetworkKind.unknown,
            peer: AppDevice.laptop,
          ),
        ),
      );
      expect(find.byType(Text), findsNothing);
    });
  });

  group('animation', () {
    testWidgets('dashes drift while looking', (tester) async {
      await tester.pumpWidget(
        _host(
          const LinkIndicator(state: LinkState.looking, peer: AppDevice.laptop),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(SchedulerBinding.instance.transientCallbackCount, greaterThan(0));
    });

    testWidgets('no animation when animations are disabled', (tester) async {
      await tester.pumpWidget(
        _host(
          const LinkIndicator(state: LinkState.looking, peer: AppDevice.laptop),
          disableAnimations: true,
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(SchedulerBinding.instance.transientCallbackCount, 0);
    });

    testWidgets('solid and broken states never animate', (tester) async {
      for (final state in [LinkState.connected, LinkState.offline]) {
        await tester.pumpWidget(
          _host(LinkIndicator(state: state, peer: AppDevice.laptop)),
        );
        await tester.pump(
          const Duration(milliseconds: 500),
        ); // Lets the theme-change animation of a rebuilt MaterialApp finish.
        expect(
          SchedulerBinding.instance.transientCallbackCount,
          0,
          reason: state.name,
        );
      }
    });

    testWidgets('stops drifting when the state changes to connected', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const LinkIndicator(state: LinkState.looking, peer: AppDevice.laptop),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpWidget(
        _host(
          const LinkIndicator(
            state: LinkState.connected,
            peer: AppDevice.laptop,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(SchedulerBinding.instance.transientCallbackCount, 0);
    });
  });

  group('golden images', () {
    for (final brightness in Brightness.values) {
      for (final state in LinkState.values) {
        testWidgets('${state.name} ${brightness.name}', (tester) async {
          tester.view.physicalSize = const Size(420, 140);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);

          await tester.pumpWidget(
            _host(
              LinkIndicator(
                state: state,
                network: state == LinkState.offline
                    ? NetworkKind.unknown
                    : NetworkKind.wifi,
                peer: AppDevice.laptop,
              ),
              brightness: brightness,
              disableAnimations: true,
            ),
          );
          await expectLater(
            find.byType(Scaffold),
            matchesGoldenFile(
              'goldens/link_indicator_${state.name}_${brightness.name}.png',
            ),
          );
        });
      }
    }
  });
}

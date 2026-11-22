import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:personal_sender/core/discovery/discovery.dart' show NetworkKind;
import 'package:personal_sender/core/history/history_store.dart';
import 'package:personal_sender/desktop/drop_zone.dart';
import 'package:personal_sender/desktop/main_window.dart';
import 'package:personal_sender/shared_ui/activity_row.dart';
import 'package:personal_sender/shared_ui/link_indicator.dart';
import 'package:personal_sender/shared_ui/sending_progress.dart';
import 'package:personal_sender/shared_ui/theme.dart';
import 'package:personal_sender/shared_ui/tokens.dart';

HistoryItem _item(
  String id, {
  HistoryDirection direction = HistoryDirection.sent,
  HistoryStatus status = HistoryStatus.done,
  String title = '3 photos',
  String? reason,
}) => HistoryItem(
  id: id,
  direction: direction,
  status: status,
  kind: HistoryKind.photo,
  title: title,
  count: 3,
  totalBytes: 8200000,
  time: DateTime(2026, 11, 22, 15, 42),
  peerName: 'Galaxy S24 Ultra',
  failureReason: reason,
);

class _Calls {
  int choose = 0;
  int pair = 0;
  int folder = 0;
  int tryAgain = 0;
  final List<List<String>> files = [];
}

Widget _window({
  bool paired = true,
  LinkState link = LinkState.connected,
  List<HistoryItem> activity = const [],
  SendingProgress? sending,
  _Calls? calls,
  double textScale = 1,
  Brightness brightness = Brightness.light,
}) {
  final c = calls ?? _Calls();
  return MaterialApp(
    theme: buildTheme(AppDevice.laptop, brightness),
    home: MediaQuery(
      data: MediaQueryData(
        textScaler: TextScaler.linear(textScale),
        disableAnimations: true,
      ),
      child: MainWindow(
        paired: paired,
        link: link,
        network: NetworkKind.wifi,
        peerName: 'Galaxy S24 Ultra',
        activity: activity,
        sending: sending,
        onFiles: c.files.add,
        onChoose: () => c.choose++,
        onPair: () => c.pair++,
        onOpenFolder: () => c.folder++,
        onTryAgain: () => c.tryAgain++,
      ),
    ),
  );
}

void _size(WidgetTester tester, double width, [double height = 720]) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// The label of the button that currently has keyboard focus.
String? _focusedButtonLabel() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return null;
  String? label;
  context.visitAncestorElements((element) {
    final widget = element.widget;
    if (widget is ButtonStyleButton) {
      final child = widget.child;
      label = child is Text ? child.data : null;
      return false;
    }
    return true;
  });
  return label;
}

void main() {
  group('states', () {
    testWidgets('connected', (tester) async {
      _size(tester, 1000);
      await tester.pumpWidget(_window());
      expect(find.text('Connected'), findsOneWidget);
      expect(find.text('Ready to send to Galaxy S24 Ultra.'), findsOneWidget);
      expect(find.byType(LinkIndicator), findsOneWidget);
      expect(find.byType(DropZone), findsOneWidget);
      expect(find.text('Choose files…'), findsOneWidget);
      expect(find.text('Open received folder'), findsOneWidget);
      expect(find.text('Pair phone'), findsOneWidget);
    });

    testWidgets('looking', (tester) async {
      _size(tester, 1000);
      await tester.pumpWidget(_window(link: LinkState.looking));
      expect(find.text('Looking for your phone'), findsOneWidget);
    });

    testWidgets('offline: design text, Try again, drop zone still there', (
      tester,
    ) async {
      _size(tester, 1000);
      final calls = _Calls();
      await tester.pumpWidget(_window(link: LinkState.offline, calls: calls));
      expect(find.text('Not reachable'), findsOneWidget);
      expect(
        find.text(
          'Not reachable. Open PersonalSender on the phone and join the '
          'same Wi-Fi or hotspot.',
        ),
        findsOneWidget,
      );
      // The drop zone keeps accepting files, and Choose files… still works.
      expect(find.byType(DropZone), findsOneWidget);
      await tester.tap(find.text('Choose files…'));
      expect(calls.choose, 1);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Try again'));
      expect(calls.tryAgain, 1);
    });

    testWidgets('not paired: Pair phone button in the card and header', (
      tester,
    ) async {
      _size(tester, 1000);
      await tester.pumpWidget(_window(paired: false));
      expect(find.text('Not paired'), findsOneWidget);
      expect(find.byType(LinkIndicator), findsNothing);
      expect(find.text('Pair phone'), findsNWidgets(2));
    });

    testWidgets('sending: progress shown and Choose files disabled', (
      tester,
    ) async {
      _size(tester, 1000);
      await tester.pumpWidget(
        _window(
          sending: const SendingProgress(
            label: 'Sending 2 of 3 · 18.4 of 41.0 MB',
            fraction: 0.5,
          ),
        ),
      );
      expect(find.text('Sending 2 of 3 · 18.4 of 41.0 MB'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      final choose = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Choose files…'),
      );
      expect(choose.onPressed, isNull);
    });

    testWidgets('header buttons call back', (tester) async {
      _size(tester, 1000);
      final calls = _Calls();
      await tester.pumpWidget(_window(calls: calls));
      await tester.tap(find.text('Pair phone'));
      await tester.tap(find.text('Open received folder'));
      expect(calls.pair, 1);
      expect(calls.folder, 1);
    });
  });

  group('drop zone look', () {
    Widget view({required bool dragging}) => MaterialApp(
      theme: buildTheme(AppDevice.laptop, Brightness.light),
      home: Scaffold(
        body: DropZoneView(dragging: dragging, onChoose: () {}),
      ),
    );

    testWidgets('idle shows the invitation and Choose files…', (tester) async {
      await tester.pumpWidget(view(dragging: false));
      expect(find.text('Drop files here'), findsOneWidget);
      expect(find.text('Choose files…'), findsOneWidget);
      expect(find.text('Ctrl+O'), findsOneWidget);
    });

    testWidgets('drag-over: laptopSoft fill, phone badge, Drop to send', (
      tester,
    ) async {
      await tester.pumpWidget(view(dragging: true));
      expect(find.text('Drop to send'), findsOneWidget);
      expect(find.byIcon(Icons.smartphone), findsOneWidget);
      expect(find.text('Choose files…'), findsNothing);

      final colors = buildTheme(
        AppDevice.laptop,
        Brightness.light,
      ).extension<DeviceColors>()!;
      final box = tester.widget<AnimatedContainer>(
        find.byType(AnimatedContainer),
      );
      expect((box.decoration! as BoxDecoration).color, colors.laptopSoft);
    });
  });

  group('layout', () {
    Rect rectOf(WidgetTester t, Finder f) => t.getRect(f);

    testWidgets('wide: Activity sits beside the drop zone', (tester) async {
      _size(tester, 1000);
      await tester.pumpWidget(_window(activity: [_item('1')]));
      final zone = rectOf(tester, find.byType(DropZoneView));
      final activity = rectOf(tester, find.text('Activity'));
      expect(activity.left, greaterThanOrEqualTo(zone.right));
    });

    testWidgets('below 760 px: Activity stacks under the drop zone', (
      tester,
    ) async {
      _size(tester, 700, 1400);
      await tester.pumpWidget(_window(activity: [_item('1')]));
      final zone = rectOf(tester, find.byType(DropZoneView));
      final activity = rectOf(tester, find.text('Activity'));
      expect(activity.top, greaterThanOrEqualTo(zone.bottom));
    });

    testWidgets('the breakpoint is exactly 760', (tester) async {
      _size(tester, 759, 1400);
      await tester.pumpWidget(_window(activity: [_item('1')]));
      expect(
        rectOf(tester, find.text('Activity')).top,
        greaterThanOrEqualTo(rectOf(tester, find.byType(DropZoneView)).bottom),
      );
      _size(tester, 760, 1400);
      await tester.pumpWidget(_window(activity: [_item('1')]));
      await tester.pump();
      expect(
        rectOf(tester, find.text('Activity')).left,
        greaterThanOrEqualTo(rectOf(tester, find.byType(DropZoneView)).right),
      );
    });
  });

  group('Activity list', () {
    testWidgets('empty text, then rows coloured by origin device', (
      tester,
    ) async {
      _size(tester, 1000);
      await tester.pumpWidget(_window());
      expect(find.text('Nothing sent or received yet.'), findsOneWidget);

      await tester.pumpWidget(
        _window(
          activity: [
            _item('1'),
            _item('2', direction: HistoryDirection.received, title: 'a.pdf'),
          ],
        ),
      );
      expect(find.byType(ActivityRow), findsNWidgets(2));
      final colors = buildTheme(
        AppDevice.laptop,
        Brightness.light,
      ).extension<DeviceColors>()!;
      Color tileOf(int i) {
        final box = tester.widget<Container>(
          find
              .descendant(
                of: find.byType(ActivityRow).at(i),
                matching: find.byType(Container),
              )
              .at(1),
        );
        return (box.decoration! as BoxDecoration).color!;
      }

      expect(tileOf(0), colors.laptopSoft); // sent from the laptop: blue
      expect(tileOf(1), colors.phoneSoft); // received from the phone: orange
    });
  });

  group('keyboard', () {
    testWidgets('Ctrl+O chooses files', (tester) async {
      _size(tester, 1000);
      final calls = _Calls();
      await tester.pumpWidget(_window(calls: calls));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(calls.choose, 1);
    });

    testWidgets('Ctrl+O is ignored while a batch is sending', (tester) async {
      _size(tester, 1000);
      final calls = _Calls();
      await tester.pumpWidget(
        _window(
          calls: calls,
          sending: const SendingProgress(label: 'Sending', fraction: 0.1),
        ),
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(calls.choose, 0);
    });

    testWidgets('Tab goes header buttons, then Choose files', (tester) async {
      _size(tester, 1000);
      final calls = _Calls();
      await tester.pumpWidget(_window(calls: calls));

      final order = <String?>[];
      for (var i = 0; i < 3; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        order.add(_focusedButtonLabel());
      }
      expect(order, ['Pair phone', 'Open received folder', 'Choose files…']);

      // Space or Enter activates the focused button: keyboard-only works.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(calls.choose, 1);
    });

    testWidgets('Shift+Tab goes back', (tester) async {
      _size(tester, 1000);
      await tester.pumpWidget(_window());
      for (var i = 0; i < 3; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      }
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(_focusedButtonLabel(), 'Open received folder');
    });
  });

  group('200 % text', () {
    final cases = <String, Widget Function()>{
      'connected with rows': () => _window(
        textScale: 2,
        activity: [
          _item('1'),
          _item(
            '2',
            direction: HistoryDirection.received,
            title: 'Holiday.mp4',
          ),
          _item('3', status: HistoryStatus.failed, reason: 'Not reachable'),
        ],
      ),
      'offline': () => _window(textScale: 2, link: LinkState.offline),
      'not paired': () => _window(textScale: 2, paired: false),
      'dark': () => _window(textScale: 2, brightness: Brightness.dark),
    };
    for (final width in [1000.0, 700.0]) {
      cases.forEach((name, build) {
        testWidgets('$name at ${width.toInt()} px: no overflow', (
          tester,
        ) async {
          _size(tester, width, 800);
          await tester.pumpWidget(build());
          expect(tester.takeException(), isNull);
          if (width < mainWindowWideBreakpoint) {
            // Stacked layout: the page scrolls down to Activity.
            await tester.scrollUntilVisible(
              find.text('Activity'),
              300,
              scrollable: find.byType(Scrollable).first,
            );
            expect(tester.takeException(), isNull);
          }
          expect(find.text('Activity'), findsOneWidget);
        });
      });
    }
  });
}

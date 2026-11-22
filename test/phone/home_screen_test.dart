import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:personal_sender/core/discovery/discovery.dart' show NetworkKind;
import 'package:personal_sender/core/history/history_store.dart';
import 'package:personal_sender/phone/home_screen.dart';
import 'package:personal_sender/shared_ui/activity_row.dart';
import 'package:personal_sender/shared_ui/link_indicator.dart';
import 'package:personal_sender/shared_ui/theme.dart';
import 'package:personal_sender/shared_ui/tokens.dart';

HistoryItem _item(
  String id, {
  HistoryDirection direction = HistoryDirection.sent,
  HistoryStatus status = HistoryStatus.done,
  String title = '4 photos',
  String? reason,
}) => HistoryItem(
  id: id,
  direction: direction,
  status: status,
  kind: HistoryKind.photo,
  title: title,
  count: 4,
  totalBytes: 12400000,
  time: DateTime(2026, 11, 22, 15, 42),
  peerName: 'Laptop',
  failureReason: reason,
);

class _Calls {
  int media = 0;
  int files = 0;
  int tryAgain = 0;
  int pair = 0;
}

Widget _home({
  bool paired = true,
  LinkState link = LinkState.connected,
  List<HistoryItem> today = const [],
  SendingProgress? sending,
  _Calls? calls,
  double textScale = 1,
  Brightness brightness = Brightness.light,
  Size size = const Size(412, 892),
}) {
  final c = calls ?? _Calls();
  return MaterialApp(
    theme: buildTheme(AppDevice.phone, brightness),
    home: MediaQuery(
      data: MediaQueryData(
        size: size,
        textScaler: TextScaler.linear(textScale),
        padding: const EdgeInsets.only(top: 32, bottom: 16),
        disableAnimations: true,
      ),
      child: HomeScreen(
        paired: paired,
        link: link,
        network: NetworkKind.wifi,
        peerName: 'Laptop',
        today: today,
        sending: sending,
        onSendMedia: () => c.media++,
        onSendFiles: () => c.files++,
        onTryAgain: () => c.tryAgain++,
        onPair: () => c.pair++,
      ),
    ),
  );
}

Finder _button(String label) => find.widgetWithText(FilledButton, label);

bool _enabled(WidgetTester tester, String label) =>
    tester.widget<FilledButton>(_button(label)).onPressed != null;

void _phoneSize(WidgetTester tester, [Size size = const Size(412, 892)]) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  group('states', () {
    testWidgets('connected: names the state and enables sending', (
      tester,
    ) async {
      _phoneSize(tester);
      final calls = _Calls();
      await tester.pumpWidget(_home(calls: calls));
      expect(find.text('Connected'), findsOneWidget);
      expect(find.text('Ready to send to Laptop.'), findsOneWidget);
      expect(_enabled(tester, 'Send photos & videos'), isTrue);
      expect(_enabled(tester, 'Send files'), isTrue);

      await tester.tap(_button('Send photos & videos'));
      await tester.tap(_button('Send files'));
      expect(calls.media, 1);
      expect(calls.files, 1);
    });

    testWidgets('looking: buttons disabled with an explanation', (
      tester,
    ) async {
      _phoneSize(tester);
      await tester.pumpWidget(_home(link: LinkState.looking));
      expect(find.text('Looking for your laptop'), findsOneWidget);
      expect(_enabled(tester, 'Send photos & videos'), isFalse);
      expect(_enabled(tester, 'Send files'), isFalse);
      expect(
        find.textContaining('Open PersonalSender on the laptop'),
        findsOneWidget,
      );
    });

    testWidgets('offline: disabled buttons, the design text and Try again', (
      tester,
    ) async {
      _phoneSize(tester);
      final calls = _Calls();
      await tester.pumpWidget(_home(link: LinkState.offline, calls: calls));
      expect(find.text('Not reachable'), findsOneWidget);
      expect(
        find.text(
          'Not reachable. Open PersonalSender on the laptop and join the '
          'same Wi-Fi or hotspot.',
        ),
        findsOneWidget,
      );
      expect(_enabled(tester, 'Send photos & videos'), isFalse);
      expect(_enabled(tester, 'Send files'), isFalse);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Try again'));
      expect(calls.tryAgain, 1);
    });

    testWidgets('not paired: Pair button, no connection line', (tester) async {
      _phoneSize(tester);
      final calls = _Calls();
      await tester.pumpWidget(_home(paired: false, calls: calls));
      expect(find.text('Not paired'), findsOneWidget);
      expect(find.byType(LinkIndicator), findsNothing);
      expect(_enabled(tester, 'Send photos & videos'), isFalse);
      await tester.tap(find.widgetWithText(FilledButton, 'Pair'));
      expect(calls.pair, 1);
    });

    testWidgets('sending: progress is shown and buttons are disabled', (
      tester,
    ) async {
      _phoneSize(tester);
      await tester.pumpWidget(
        _home(
          sending: const SendingProgress(
            label: 'Sending 2 of 4 · 18.4 of 41.0 MB',
            fraction: 0.45,
          ),
        ),
      );
      expect(find.text('Sending 2 of 4 · 18.4 of 41.0 MB'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(_enabled(tester, 'Send photos & videos'), isFalse);
    });

    testWidgets('Stay ready is shown but cannot be switched yet', (
      tester,
    ) async {
      _phoneSize(tester);
      await tester.pumpWidget(_home());
      expect(find.text('Stay ready'), findsOneWidget);
      expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
    });
  });

  group('Today list', () {
    testWidgets('empty message, then rows when there are items', (
      tester,
    ) async {
      _phoneSize(tester);
      await tester.pumpWidget(_home());
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Nothing sent or received today yet.'), findsOneWidget);

      await tester.pumpWidget(
        _home(
          today: [
            _item('1'),
            _item('2', title: 'IMG_9.jpg'),
          ],
        ),
      );
      expect(find.byType(ActivityRow), findsNWidgets(2));
      expect(find.text('4 photos'), findsOneWidget);
      expect(find.text('Nothing sent or received today yet.'), findsNothing);
    });
  });

  group('ActivityRow', () {
    Future<void> pumpRow(
      WidgetTester tester,
      HistoryItem item, {
      VoidCallback? onRetry,
    }) => tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(AppDevice.phone, Brightness.light),
        home: Scaffold(
          body: ActivityRow(
            item: item,
            thisDevice: AppDevice.phone,
            onRetry: onRetry,
          ),
        ),
      ),
    );

    BoxDecoration tile(WidgetTester tester) {
      final box = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(ActivityRow),
              matching: find.byType(Container),
            )
            .at(1),
      );
      return box.decoration! as BoxDecoration;
    }

    testWidgets('a sent item has the phone-orange tile and words', (
      tester,
    ) async {
      await pumpRow(tester, _item('1'));
      final colors = buildTheme(
        AppDevice.phone,
        Brightness.light,
      ).extension<DeviceColors>()!;
      expect(tile(tester).color, colors.phoneSoft);
      expect(find.textContaining('To Laptop'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
      expect(find.textContaining('12.4 MB'), findsOneWidget);
    });

    testWidgets('a received item has the laptop-blue tile and From', (
      tester,
    ) async {
      await pumpRow(tester, _item('1', direction: HistoryDirection.received));
      final colors = buildTheme(
        AppDevice.phone,
        Brightness.light,
      ).extension<DeviceColors>()!;
      expect(tile(tester).color, colors.laptopSoft);
      expect(find.textContaining('From Laptop'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
    });

    testWidgets('failed: rose tile, icon, Not sent · reason, Retry', (
      tester,
    ) async {
      var retried = 0;
      await pumpRow(
        tester,
        _item('1', status: HistoryStatus.failed, reason: 'Not reachable'),
        onRetry: () => retried++,
      );
      final colors = buildTheme(
        AppDevice.phone,
        Brightness.light,
      ).extension<DeviceColors>()!;
      expect(tile(tester).color, colors.dangerSoft);
      expect(find.text('Not sent · Not reachable'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      await tester.tap(find.text('Retry'));
      expect(retried, 1);
    });

    testWidgets('waiting: clock and the word Waiting', (tester) async {
      await pumpRow(tester, _item('1', status: HistoryStatus.waiting));
      expect(find.byIcon(Icons.schedule), findsOneWidget);
      expect(find.textContaining('Waiting'), findsOneWidget);
    });

    testWidgets('no Retry button without a callback', (tester) async {
      await pumpRow(tester, _item('1', status: HistoryStatus.failed));
      expect(find.text('Retry'), findsNothing);
    });
  });

  group('200 % text', () {
    final scenarios = <String, Widget Function()>{
      'connected with rows': () => _home(
        textScale: 2,
        today: [
          _item('1'),
          _item(
            '2',
            direction: HistoryDirection.received,
            title: 'Holiday.mp4',
          ),
          _item('3', status: HistoryStatus.failed, reason: 'Not reachable'),
        ],
      ),
      'offline': () => _home(textScale: 2, link: LinkState.offline),
      'looking': () => _home(textScale: 2, link: LinkState.looking),
      'not paired': () => _home(textScale: 2, paired: false),
      'sending': () => _home(
        textScale: 2,
        sending: const SendingProgress(
          label: 'Sending 2 of 4 · 18.4 of 41.0 MB · 12 MB/s',
          fraction: 0.4,
        ),
      ),
      'dark mode': () => _home(
        textScale: 2,
        brightness: Brightness.dark,
        link: LinkState.offline,
      ),
    };

    scenarios.forEach((name, build) {
      testWidgets('$name: no overflow and everything can be reached', (
        tester,
      ) async {
        _phoneSize(tester, const Size(360, 780));
        await tester.pumpWidget(build());
        expect(tester.takeException(), isNull);

        // The page scrolls, so the Today heading must be reachable.
        await tester.scrollUntilVisible(
          find.text('Today'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Today'), findsOneWidget);
        // The send buttons stay on screen in their own bar.
        expect(_button('Send photos & videos'), findsOneWidget);
        expect(_button('Send files'), findsOneWidget);
      });
    });
  });
}

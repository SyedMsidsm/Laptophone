import 'dart:io';

import 'package:material_ui/material_ui.dart';

import 'desktop/laptop_host.dart';
import 'core/history/history_store.dart';
import 'core/identity/identity.dart';
import 'core/storage/paired_store.dart';
import 'phone/phone_home_host.dart';
import 'shared_ui/flutter_secret_store.dart';
import 'shared_ui/shared_prefs_store.dart';
import 'shared_ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final sw = Stopwatch()..start();
  final identity = await DeviceIdentity.loadOrCreate(
    const FlutterSecretStore(),
    name: Platform.localHostname,
  );
  debugPrint('Identity ready in ${sw.elapsedMilliseconds} ms');
  final android = Platform.isAndroid;
  final pairedStore = PairedDeviceStore(const FlutterSecretStore());
  if (android) {
    // The real phone Home screen (Task 12).
    final history = HistoryStore(await SharedPrefsStore.open());
    runApp(
      PersonalSenderApp(
        device: AppDevice.phone,
        home: PhoneHomeHost(
          identity: identity,
          pairedStore: pairedStore,
          history: history,
        ),
      ),
    );
    return;
  }
  // The laptop main window (Task 13).
  final history = HistoryStore(await SharedPrefsStore.open());
  runApp(
    PersonalSenderApp(
      device: AppDevice.laptop,
      home: LaptopHost(
        identity: identity,
        pairedStore: pairedStore,
        history: history,
      ),
    ),
  );
}

class PersonalSenderApp extends StatelessWidget {
  const PersonalSenderApp({
    super.key,
    this.home,
    this.device = AppDevice.phone,
  });

  final Widget? home;
  final AppDevice device;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PersonalSender',
      theme: buildTheme(device, Brightness.light),
      darkTheme: buildTheme(device, Brightness.dark),
      themeMode: ThemeMode.system,
      home: home ?? const Scaffold(body: Center(child: Text('PersonalSender'))),
    );
  }
}

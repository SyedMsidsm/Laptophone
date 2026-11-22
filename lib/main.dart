import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import 'desktop/known_folders.dart';
import 'core/identity/identity.dart';
import 'shared_ui/dev_transfer_screen.dart';
import 'shared_ui/flutter_secret_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final sw = Stopwatch()..start();
  final identity = await DeviceIdentity.loadOrCreate(
    const FlutterSecretStore(),
    name: Platform.localHostname,
  );
  debugPrint('Identity ready in ${sw.elapsedMilliseconds} ms');
  // Task 4 dev screen on both devices; replaced by the real apps later.
  final android = Platform.isAndroid;
  runApp(
    PersonalSenderApp(
      home: DevTransferScreen(
        identity: identity,
        platform: android ? 'android' : 'windows',
        // Phone: app cache for now (real Downloads/gallery saving is Task 14).
        resolveInbox: android
            ? () async => Directory('${Directory.systemTemp.path}/inbox')
            : personalSenderInbox,
        pickType: android ? FileType.image : FileType.any,
        pickLabel: android ? 'Pick photo' : 'Pick file',
      ),
    ),
  );
}

class PersonalSenderApp extends StatelessWidget {
  const PersonalSenderApp({super.key, this.home});

  final Widget? home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PersonalSender',
      home: home ?? const Scaffold(body: Center(child: Text('PersonalSender'))),
    );
  }
}

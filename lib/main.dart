import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import 'desktop/known_folders.dart';
import 'shared_ui/dev_transfer_screen.dart';

void main() {
  // Task 4 dev screen on both devices; replaced by the real apps later.
  final android = Platform.isAndroid;
  runApp(
    PersonalSenderApp(
      home: DevTransferScreen(
        deviceName: Platform.localHostname,
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

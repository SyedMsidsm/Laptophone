import 'dart:io';

/// Resolves the real Windows Desktop folder, including OneDrive-redirected
/// desktops, by reading the "User Shell Folders" registry value.
Future<Directory> windowsDesktopFolder() async {
  final profile = Platform.environment['USERPROFILE'] ?? '';
  try {
    final r = await Process.run('reg', [
      'query',
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders',
      '/v',
      'Desktop',
    ]);
    if (r.exitCode == 0) {
      final m = RegExp(r'Desktop\s+REG_(?:EXPAND_)?SZ\s+(.+)')
          .firstMatch(r.stdout as String);
      if (m != null) {
        final expanded = m
            .group(1)!
            .trim()
            .replaceAllMapped(
              RegExp('%([^%]+)%'),
              (v) => Platform.environment[v.group(1)!] ?? v.group(0)!,
            );
        if (!expanded.contains('%')) return Directory(expanded);
      }
    }
  } catch (_) {
    // Fall through to the default below.
  }
  return Directory('$profile${Platform.pathSeparator}Desktop');
}

/// `Desktop\PersonalSender Inbox`
Future<Directory> personalSenderInbox() async {
  final desktop = await windowsDesktopFolder();
  return Directory(
    '${desktop.path}${Platform.pathSeparator}PersonalSender Inbox',
  );
}

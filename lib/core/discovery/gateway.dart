import 'dart:io';

/// What this device knows about its network. Apps provide an implementation
/// (the phone uses `network_info_plus` for the gateway).
abstract interface class NetworkInfoProvider {
  /// This device's private IPv4 addresses on real networks (no loopback,
  /// link-local, mobile data or virtual adapters).
  Future<List<String>> localAddresses();

  /// The default gateway, or null when there is none (for example when this
  /// device hosts the hotspot, or has no network).
  Future<String?> gateway();
}

/// True for 10/8, 172.16/12 and 192.168/16.
bool isPrivateIPv4(String address) {
  final p = address.split('.');
  if (p.length != 4) return false;
  final a = int.tryParse(p[0]);
  final b = int.tryParse(p[1]);
  if (a == null || b == null) return false;
  return a == 10 || (a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168);
}

/// Adapter names that never lead to the paired device.
bool isVirtualInterface(String name) {
  final n = name.toLowerCase();
  return n.contains('vethernet') ||
      n.contains('wsl') ||
      n.contains('docker') ||
      n.contains('vmware') ||
      n.contains('virtualbox') ||
      n.contains('rmnet') ||
      n == 'lo' ||
      n == 'lo0';
}

/// Lists usable private IPv4 addresses using `dart:io` only.
Future<List<String>> listLocalAddresses() async {
  final found = <String>[];
  for (final i in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
    if (isVirtualInterface(i.name)) continue;
    for (final a in i.addresses) {
      if (isPrivateIPv4(a.address) && !found.contains(a.address)) {
        found.add(a.address);
      }
    }
  }
  return found;
}

/// Reads the default gateway from the Windows routing table.
Future<String?> windowsDefaultGateway() async {
  try {
    final r = await Process.run('route', ['print', '-4', '0.0.0.0']);
    if (r.exitCode != 0) return null;
    return parseWindowsRoutePrint(r.stdout as String);
  } on Object {
    return null;
  }
}

/// Picks the default route with the lowest metric from `route print -4`.
String? parseWindowsRoutePrint(String output) {
  String? best;
  var bestMetric = 1 << 30;
  final line = RegExp(
    r'^\s*0\.0\.0\.0\s+0\.0\.0\.0\s+(\d+\.\d+\.\d+\.\d+)\s+\d+\.\d+\.\d+\.\d+\s+(\d+)',
    multiLine: true,
  );
  for (final m in line.allMatches(output)) {
    final gateway = m.group(1)!;
    final metric = int.parse(m.group(2)!);
    if (gateway != '0.0.0.0' && metric < bestMetric) {
      best = gateway;
      bestMetric = metric;
    }
  }
  return best;
}

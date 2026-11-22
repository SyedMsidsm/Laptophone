import 'dart:io';

import 'package:network_info_plus/network_info_plus.dart';

import '../core/discovery/discovery.dart';

/// [NetworkInfoProvider] for the real devices: `network_info_plus` gives the
/// phone's Wi-Fi gateway, and the Windows routing table gives the laptop's.
class PlatformNetworkInfo implements NetworkInfoProvider {
  PlatformNetworkInfo();

  @override
  Future<List<String>> localAddresses() => listLocalAddresses();

  @override
  Future<String?> gateway() async {
    if (Platform.isAndroid) {
      try {
        final g = await NetworkInfo().getWifiGatewayIP();
        return (g == null || g.isEmpty || g == '0.0.0.0') ? null : g;
      } on Object {
        return null;
      }
    }
    return windowsDefaultGateway();
  }
}

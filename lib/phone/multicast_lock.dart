import 'dart:io';

import 'package:flutter/services.dart';

/// Holds Android's `WifiManager.MulticastLock` so the phone receives UDP
/// multicast and broadcast while the app is open. Does nothing elsewhere.
class MulticastLock {
  const MulticastLock();

  static const _channel = MethodChannel('com.personalsender.app/multicast');

  /// Returns true when the lock is held.
  Future<bool> acquire() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('acquire') ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> release() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('release');
    } on PlatformException {
      // Nothing to release.
    }
  }
}

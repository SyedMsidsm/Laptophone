import 'package:shared_preferences/shared_preferences.dart';

import '../core/storage/key_value_store.dart';

/// [KeyValueStore] backed by `shared_preferences`.
class SharedPrefsStore implements KeyValueStore {
  const SharedPrefsStore(this._prefs);

  final SharedPreferences _prefs;

  static Future<SharedPrefsStore> open() async =>
      SharedPrefsStore(await SharedPreferences.getInstance());

  @override
  Future<String?> read(String key) async => _prefs.getString(key);

  @override
  Future<void> write(String key, String value) async {
    await _prefs.setString(key, value);
  }
}

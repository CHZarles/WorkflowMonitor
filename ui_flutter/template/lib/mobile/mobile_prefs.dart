import "package:shared_preferences/shared_preferences.dart";

class MobilePrefs {
  static const String blockMinutesKey = "mobileBlockMinutes";
  static const int defaultBlockMinutes = 45;

  static int _clampBlockMinutes(int v) => v.clamp(5, 240);

  static Future<int> getBlockMinutes() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getInt(blockMinutesKey) ?? defaultBlockMinutes;
    return _clampBlockMinutes(v);
  }

  static Future<void> setBlockMinutes(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(blockMinutesKey, _clampBlockMinutes(minutes));
  }
}


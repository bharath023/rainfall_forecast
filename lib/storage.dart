import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// Small persisted settings, shared by the UI and the background alert task.
class Storage {
  static const _placeKey = 'place';
  static const _alertsKey = 'alerts_enabled';
  static const _lastAlertKey = 'last_alert_ms';
  static const _themeKey = 'theme_mode';

  static Future<Place?> loadPlace() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_placeKey);
    if (raw == null) return null;
    try {
      return Place.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<void> savePlace(Place place) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_placeKey, jsonEncode(place.toJson()));
  }

  static Future<bool> alertsEnabled() async =>
      (await SharedPreferences.getInstance()).getBool(_alertsKey) ?? false;

  static Future<void> setAlertsEnabled(bool on) async =>
      (await SharedPreferences.getInstance()).setBool(_alertsKey, on);

  /// 'system', 'light' or 'dark'.
  static Future<String> themeMode() async =>
      (await SharedPreferences.getInstance()).getString(_themeKey) ?? 'system';

  static Future<void> setThemeMode(String mode) async =>
      (await SharedPreferences.getInstance()).setString(_themeKey, mode);

  static Future<DateTime?> lastAlert() async {
    final ms = (await SharedPreferences.getInstance()).getInt(_lastAlertKey);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  static Future<void> setLastAlert(DateTime t) async =>
      (await SharedPreferences.getInstance())
          .setInt(_lastAlertKey, t.millisecondsSinceEpoch);
}

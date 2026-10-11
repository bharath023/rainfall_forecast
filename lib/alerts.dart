import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:workmanager/workmanager.dart';

import 'models.dart';
import 'storage.dart';

/// Background rain alerts: every ~30 min the OS wakes the app, which checks
/// the next 3 hours at the saved place and notifies if rain is coming.
///
/// This runs on the device (no server needed). Android is fully set up; iOS
/// additionally needs BGTaskScheduler registration in AppDelegate (see README),
/// and iOS decides itself how often background fetch actually runs.
class RainAlerts {
  static const _uniqueName = 'rain-check';
  static const _taskName = 'rainCheck';

  /// Rain at or above this in any of the next 3 hours triggers an alert...
  static const thresholdMm = 0.5;

  /// ...as does a chance of rain at or above this (percent).
  static const thresholdProbability = 60;

  /// Don't repeat an alert within this window.
  static const quietPeriod = Duration(hours: 3);

  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static final _notifications = FlutterLocalNotificationsPlugin();

  /// Call once from main() before runApp.
  static Future<void> init() async {
    if (!isSupported) return;
    await Workmanager().initialize(rainAlertsDispatcher);
  }

  static Future<void> _initNotifications() async {
    await _notifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
  }

  /// Asks for notification permission and schedules the periodic check.
  /// Returns false if the user refused permission.
  static Future<bool> enable() async {
    await _initNotifications();
    final granted = await _notifications
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission() ??
        await _notifications
            .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(alert: true, sound: true) ??
        false;
    if (!granted) return false;

    await Workmanager().registerPeriodicTask(
      _uniqueName,
      _taskName,
      frequency: const Duration(minutes: 30),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    );
    await Storage.setAlertsEnabled(true);
    // Check straight away so the user gets immediate feedback.
    await checkAndNotify(force: true);
    return true;
  }

  static Future<void> disable() async {
    await Storage.setAlertsEnabled(false);
    if (isSupported) await Workmanager().cancelByUniqueName(_uniqueName);
  }

  /// Fetches the next 3 hours and shows a notification if rain is expected.
  static Future<void> checkAndNotify({bool force = false}) async {
    if (!await Storage.alertsEnabled()) return;
    final place = await Storage.loadPlace();
    if (place == null) return;

    final last = await Storage.lastAlert();
    if (!force &&
        last != null &&
        DateTime.now().difference(last) < quietPeriod) {
      return;
    }

    final rain = await upcomingRain(place);
    if (rain == null) return;

    await _initNotifications();
    await _notifications.show(
      id: 1,
      title: 'Rain expected in ${place.name}',
      body: rain,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'rain_alerts',
          'Rain alerts',
          channelDescription:
              'Heads-up when rain is expected in the next 3 hours',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
    await Storage.setLastAlert(DateTime.now());
  }

  /// Returns a short description of the first rainy hour in the next 3 hours,
  /// or null if it looks dry. Uses Open-Meteo's best-match model blend.
  static Future<String?> upcomingRain(Place place) async {
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': '${place.lat}',
      'longitude': '${place.lon}',
      'hourly': 'precipitation,precipitation_probability',
      'forecast_hours': '3',
      'timezone': 'auto',
    });
    final res = await http.get(uri).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) return null;
    final hourly = (jsonDecode(res.body) as Map<String, dynamic>)['hourly']
        as Map<String, dynamic>;
    final times = (hourly['time'] as List).cast<String>();
    final mm = hourly['precipitation'] as List;
    final prob = hourly['precipitation_probability'] as List;

    for (var i = 0; i < times.length; i++) {
      final amount = (mm[i] as num?)?.toDouble() ?? 0;
      final chance = (prob[i] as num?)?.toInt() ?? 0;
      if (amount >= thresholdMm || chance >= thresholdProbability) {
        final hour = times[i].substring(11, 16);
        final when = i == 0 ? 'this hour' : 'around $hour';
        return '${amount.toStringAsFixed(1)} mm expected $when ($chance% chance).';
      }
    }
    return null;
  }
}

/// Entry point the OS calls in a background isolate. Must be top-level.
@pragma('vm:entry-point')
void rainAlertsDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await RainAlerts.checkAndNotify();
    } catch (_) {
      // A failed check is not worth retrying; the next period will run anyway.
    }
    return true;
  });
}

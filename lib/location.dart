import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import 'models.dart';

class LocationException implements Exception {
  final String message;
  LocationException(this.message);
  @override
  String toString() => message;
}

/// Gets the device position and turns it into a [Place].
class LocationService {
  static Future<Place> currentPlace() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw LocationException('Location services are turned off.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw LocationException('Location permission was denied.');
    }

    final pos = await _position();
    return _reverseGeocode(pos.latitude, pos.longitude);
  }

  /// City-level accuracy is plenty for a 10–25 km model grid, so try the
  /// cheapest sources first: a recent cached fix, then a low-power fix
  /// (Wi-Fi/cell), then GPS. Low-power fixes never arrive on phones where
  /// network location is off, hence the GPS fallback.
  static Future<Position> _position() async {
    final isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

    if (!kIsWeb) {
      final last = await Geolocator.getLastKnownPosition(
          forceAndroidLocationManager: true);
      if (last != null &&
          DateTime.now().difference(last.timestamp) <
              const Duration(hours: 1)) {
        return last;
      }
    }

    // On Android, use the platform LocationManager rather than Play Services
    // so users aren't prompted to enable Google Location Accuracy.
    LocationSettings settings(LocationAccuracy accuracy, int seconds) =>
        isAndroid
            ? AndroidSettings(
                accuracy: accuracy,
                forceLocationManager: true,
                timeLimit: Duration(seconds: seconds),
              )
            : LocationSettings(
                accuracy: accuracy,
                timeLimit: Duration(seconds: seconds),
              );

    try {
      return await Geolocator.getCurrentPosition(
          locationSettings: settings(LocationAccuracy.low, 8));
    } on TimeoutException {
      return Geolocator.getCurrentPosition(
          locationSettings: settings(LocationAccuracy.high, 25));
    }
  }

  /// Free, key-less reverse geocoding (BigDataCloud client endpoint). Falls
  /// back to plain coordinates if it fails.
  static Future<Place> _reverseGeocode(double lat, double lon) async {
    try {
      final uri =
          Uri.https('api.bigdatacloud.net', '/data/reverse-geocode-client', {
        'latitude': '$lat',
        'longitude': '$lon',
        'localityLanguage': 'en',
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final city = (j['city'] as String?)?.isNotEmpty == true
          ? j['city'] as String
          : j['locality'] as String?;
      if (res.statusCode == 200 && city != null && city.isNotEmpty) {
        return Place(
          name: city,
          admin: j['principalSubdivision'] as String?,
          country: j['countryName'] as String?,
          lat: lat,
          lon: lon,
        );
      }
    } catch (_) {
      // Fall through to coordinates.
    }
    return Place(
      name: '${lat.toStringAsFixed(2)}, ${lon.toStringAsFixed(2)}',
      lat: lat,
      lon: lon,
    );
  }
}

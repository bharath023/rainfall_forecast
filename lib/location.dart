import 'dart:convert';

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

    // City-level accuracy is plenty for a 10–25 km model grid and saves battery.
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.low,
        timeLimit: Duration(seconds: 15),
      ),
    );
    return _reverseGeocode(pos.latitude, pos.longitude);
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

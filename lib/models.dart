import 'package:flutter/material.dart';

/// A deterministic global model available through Open-Meteo.
///
/// [weight] is the model's starting weight in the blended forecast. These are
/// rough priors (ECMWF usually verifies best globally); later, replace them
/// with weights learned from verification against observations per region.
class WeatherModel {
  final String id;
  final String name;
  final double weight;
  final Color color;

  const WeatherModel(this.id, this.name, this.weight, this.color);
}

const deterministicModels = <WeatherModel>[
  WeatherModel('ecmwf_ifs025', 'ECMWF IFS', 1.0, Color(0xFF1E88E5)),
  WeatherModel(
      'ecmwf_aifs025_single', 'ECMWF AIFS (AI)', 1.0, Color(0xFF8E24AA)),
  WeatherModel('icon_seamless', 'DWD ICON', 0.8, Color(0xFF43A047)),
  WeatherModel('gfs_seamless', 'NOAA GFS', 0.7, Color(0xFFE53935)),
  WeatherModel('gem_seamless', 'Canada GEM', 0.6, Color(0xFFFB8C00)),
  WeatherModel('jma_seamless', 'JMA', 0.6, Color(0xFF6D4C41)),
];

/// Ensembles used for rain probabilities: ECMWF ENS (51 members) + NOAA GEFS (31).
const ensembleModels = <String>['ecmwf_ifs025', 'gfs025'];

/// A location picked by the user.
class Place {
  final String name;
  final String? admin;
  final String? country;
  final double lat;
  final double lon;

  const Place({
    required this.name,
    this.admin,
    this.country,
    required this.lat,
    required this.lon,
  });

  String get label => [name, admin, country]
      .whereType<String>()
      .where((s) => s.isNotEmpty)
      .join(', ');

  Map<String, dynamic> toJson() => {
        'name': name,
        'admin': admin,
        'country': country,
        'lat': lat,
        'lon': lon
      };

  factory Place.fromJson(Map<String, dynamic> j) => Place(
        name: j['name'] as String,
        admin: j['admin'] as String?,
        country: j['country'] as String?,
        lat: (j['lat'] as num).toDouble(),
        lon: (j['lon'] as num).toDouble(),
      );
}

/// Forecast for one location from every model, plus ensemble members.
class ForecastData {
  final int utcOffsetSeconds;
  final List<DateTime> hourlyTime;

  /// model id -> precipitation (mm per hour), null where the model has no data.
  final Map<String, List<double?>> hourly;
  final List<DateTime> days;

  /// model id -> precipitation (mm per day).
  final Map<String, List<double?>> daily;

  /// For each day, the daily total from every ensemble member.
  final List<List<double>> ensembleDaily;

  const ForecastData({
    required this.utcOffsetSeconds,
    required this.hourlyTime,
    required this.hourly,
    required this.days,
    required this.daily,
    required this.ensembleDaily,
  });

  /// Current wall-clock hour at the forecast location (times from the API are
  /// in the location's own timezone, not the phone's).
  DateTime get locationNow {
    final t = DateTime.now().toUtc().add(Duration(seconds: utcOffsetSeconds));
    return DateTime(t.year, t.month, t.day, t.hour);
  }
}

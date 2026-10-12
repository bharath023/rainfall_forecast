import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Hourly model rain on a regular grid of points covering the map view.
///
/// Open-Meteo has no map tiles, so we sample an N×N grid of points in one
/// multi-location request and draw each point as a coloured cell. Each point
/// counts as one API call against Open-Meteo's free limit (10k/day), so the
/// grid is kept coarse; a production app would render its own tiles from the
/// raw GRIB data instead.
class ForecastGrid {
  final String modelId;
  final double south, west, latStep, lonStep;
  final int rows, cols;

  /// Hour start times (UTC) shared by all points.
  final List<DateTime> times;

  /// values[row * cols + col][hour] = mm in that hour.
  final List<List<double?>> values;

  ForecastGrid({
    required this.modelId,
    required this.south,
    required this.west,
    required this.latStep,
    required this.lonStep,
    required this.rows,
    required this.cols,
    required this.times,
    required this.values,
  });

  /// Corners of the cell centred on grid point (row, col).
  List<LatLng> cell(int row, int col) {
    final lat = south + row * latStep, lon = west + col * lonStep;
    final dLat = latStep / 2, dLon = lonStep / 2;
    return [
      LatLng(lat - dLat, lon - dLon),
      LatLng(lat - dLat, lon + dLon),
      LatLng(lat + dLat, lon + dLon),
      LatLng(lat + dLat, lon - dLon),
    ];
  }
}

/// Fetches [hours] of hourly rain for [modelId] on a [size]×[size] grid
/// spanning [sw]–[ne].
Future<ForecastGrid> fetchForecastGrid({
  required String modelId,
  required LatLng sw,
  required LatLng ne,
  int size = 12,
  int hours = 48,
}) async {
  final south = math.max(-85.0, sw.latitude);
  final north = math.min(85.0, ne.latitude);
  var west = sw.longitude, east = ne.longitude;
  if (east < west) east += 360; // view crosses the antimeridian
  final latStep = (north - south) / (size - 1);
  final lonStep = (east - west) / (size - 1);

  final lats = <String>[], lons = <String>[];
  for (var r = 0; r < size; r++) {
    for (var c = 0; c < size; c++) {
      var lon = west + c * lonStep;
      if (lon > 180) lon -= 360;
      lats.add((south + r * latStep).toStringAsFixed(3));
      lons.add(lon.toStringAsFixed(3));
    }
  }

  final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
    'latitude': lats.join(','),
    'longitude': lons.join(','),
    'hourly': 'precipitation',
    'models': modelId,
    'forecast_hours': '$hours',
    'timezone': 'GMT',
  });
  final res = await http.get(uri).timeout(const Duration(seconds: 30));
  final body = jsonDecode(res.body);
  if (res.statusCode != 200 || body is! List) {
    final reason = body is Map ? body['reason'] : null;
    throw Exception(reason ?? 'HTTP ${res.statusCode}');
  }

  List<DateTime> times = const [];
  final values = <List<double?>>[];
  for (final point in body) {
    final hourly =
        (point as Map<String, dynamic>)['hourly'] as Map<String, dynamic>;
    if (times.isEmpty) {
      times =
          (hourly['time'] as List).map((t) => DateTime.parse('${t}Z')).toList();
    }
    values.add((hourly['precipitation'] as List)
        .map((v) => (v as num?)?.toDouble())
        .toList());
  }

  return ForecastGrid(
    modelId: modelId,
    south: south,
    west: west,
    latStep: latStep,
    lonStep: lonStep,
    rows: size,
    cols: size,
    times: times,
    values: values,
  );
}

/// Radar-style colour scale for rain rate in mm/h; null = draw nothing.
Color? rainColor(double? mmPerHour) {
  if (mmPerHour == null || mmPerHour < 0.1) return null;
  const stops = <(double, Color)>[
    (0.1, Color(0xFF9BE1FF)),
    (0.5, Color(0xFF4FB0FF)),
    (1, Color(0xFF1E6BFF)),
    (2, Color(0xFF00C853)),
    (5, Color(0xFFFFEB3B)),
    (10, Color(0xFFFF9800)),
    (20, Color(0xFFF44336)),
    (50, Color(0xFFB000FF)),
  ];
  var color = stops.first.$2;
  for (final (threshold, c) in stops) {
    if (mmPerHour >= threshold) color = c;
  }
  return color;
}

/// Legend entries matching [rainColor].
const rainLegend = <(String, Color)>[
  ('0.1', Color(0xFF9BE1FF)),
  ('1', Color(0xFF1E6BFF)),
  ('2', Color(0xFF00C853)),
  ('5', Color(0xFFFFEB3B)),
  ('10', Color(0xFFFF9800)),
  ('20', Color(0xFFF44336)),
  ('50+', Color(0xFFB000FF)),
];

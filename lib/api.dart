import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

/// Thin client for the free Open-Meteo APIs (no key needed for non-commercial
/// use; a commercial app needs their paid plan or a self-hosted instance).
class OpenMeteoApi {
  Future<Map<String, dynamic>> _get(Uri uri) async {
    final res = await http.get(uri).timeout(const Duration(seconds: 20));
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200 || body['error'] == true) {
      throw Exception(body['reason'] ?? 'HTTP ${res.statusCode}');
    }
    return body;
  }

  Future<List<Place>> searchPlaces(String query) async {
    final json =
        await _get(Uri.https('geocoding-api.open-meteo.com', '/v1/search', {
      'name': query,
      'count': '10',
      'language': 'en',
      'format': 'json',
    }));
    final results = (json['results'] as List?) ?? const [];
    return results
        .map((r) => Place(
              name: r['name'] as String,
              admin: r['admin1'] as String?,
              country: r['country'] as String?,
              lat: (r['latitude'] as num).toDouble(),
              lon: (r['longitude'] as num).toDouble(),
            ))
        .toList();
  }

  Future<ForecastData> fetchForecast(Place place, {int days = 10}) async {
    final common = {
      'latitude': '${place.lat}',
      'longitude': '${place.lon}',
      'timezone': 'auto',
      'forecast_days': '$days',
    };
    final responses = await Future.wait([
      _get(Uri.https('api.open-meteo.com', '/v1/forecast', {
        ...common,
        'hourly': 'precipitation',
        'daily': 'precipitation_sum',
        'models': deterministicModels.map((m) => m.id).join(','),
      })),
      _get(Uri.https('ensemble-api.open-meteo.com', '/v1/ensemble', {
        ...common,
        'daily': 'precipitation_sum',
        'models': ensembleModels.join(','),
      })),
    ]);
    final det = responses[0];
    final ens = responses[1];

    final hourlyJson = det['hourly'] as Map<String, dynamic>;
    final dailyJson = det['daily'] as Map<String, dynamic>;

    // With several models, Open-Meteo suffixes each variable with the model id,
    // e.g. "precipitation_ecmwf_ifs025".
    final hourly = <String, List<double?>>{
      for (final m in deterministicModels)
        m.id: _numList(hourlyJson['precipitation_${m.id}']),
    };
    final daily = <String, List<double?>>{
      for (final m in deterministicModels)
        m.id: _numList(dailyJson['precipitation_sum_${m.id}']),
    };

    // Every ensemble key except "time" is one member (control or perturbed).
    final ensDaily = ens['daily'] as Map<String, dynamic>;
    final memberSeries = ensDaily.entries
        .where((e) => e.key.startsWith('precipitation_sum'))
        .map((e) => _numList(e.value))
        .toList();
    final dayCount = (dailyJson['time'] as List).length;
    final ensembleDaily = List.generate(dayCount, (i) {
      return [
        for (final s in memberSeries)
          if (i < s.length && s[i] != null) s[i]!,
      ];
    });

    return ForecastData(
      utcOffsetSeconds: (det['utc_offset_seconds'] as num?)?.toInt() ?? 0,
      hourlyTime: _timeList(hourlyJson['time']),
      hourly: hourly,
      days: _timeList(dailyJson['time']),
      daily: daily,
      ensembleDaily: ensembleDaily,
    );
  }

  static List<double?> _numList(dynamic v) =>
      ((v as List?) ?? const []).map((e) => (e as num?)?.toDouble()).toList();

  static List<DateTime> _timeList(dynamic v) =>
      (v as List).map((e) => DateTime.parse(e as String)).toList();
}

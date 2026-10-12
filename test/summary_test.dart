import 'package:flutter_test/flutter_test.dart';
import 'package:rainfall_app/models.dart';
import 'package:rainfall_app/summary.dart';

final now = DateTime(2026, 10, 12, 14, 5);

/// 12 fifteen-minute steps ending 14:15, 14:30, ... with the given rain.
ForecastData withNowcast(List<double> mm,
    {Map<String, List<double?>> hourly = const {},
    List<DateTime> hourlyTime = const [],
    List<List<double>> ensemble = const []}) {
  return ForecastData(
    utcOffsetSeconds: 0,
    hourlyTime: hourlyTime,
    hourly: hourly,
    days: [for (var i = 0; i < 3; i++) DateTime(2026, 10, 12 + i)],
    daily: const {},
    ensembleDaily: ensemble,
    nowcastTime: [
      for (var i = 0; i < mm.length; i++)
        DateTime(2026, 10, 12, 14, 15).add(Duration(minutes: 15 * i)),
    ],
    nowcastMm: mm,
    nowcastProbability: [for (final v in mm) v > 0 ? 80 : 5],
  );
}

void main() {
  test('rain starting soon', () {
    final d = withNowcast([0, 0, 0.4, 0.6, 0, 0]);
    // Third step covers 14:30–14:45, 25 min from 14:05.
    expect(headline(d, now: now), 'Rain starting in about 25 min');
  });

  test('raining now and stopping', () {
    final d = withNowcast([0.5, 0.3, 0, 0]);
    expect(headline(d, now: now), 'Raining now · stopping around 14:30');
  });

  test('later in the 3-hour window uses a clock time', () {
    final d = withNowcast([0, 0, 0, 0, 0, 0.2]);
    expect(headline(d, now: now), 'Rain likely from 15:15');
  });

  test('falls back to hourly blend, then ensemble days', () {
    final hourly = {
      'ecmwf_ifs025': <double?>[0, 0, 0, 0, 0, 2.0]
    };
    final hourlyTime = [
      for (var i = 0; i < 6; i++) DateTime(2026, 10, 12, 14 + i),
    ];
    expect(
        headline(withNowcast([0, 0], hourly: hourly, hourlyTime: hourlyTime),
            now: now),
        'Rain likely around 19:00');

    final ensemble = [
      <double>[0, 0],
      <double>[5, 5, 0, 5], // 75% ≥ 1 mm tomorrow
      <double>[0],
    ];
    expect(headline(withNowcast([0, 0], ensemble: ensemble), now: now),
        'Dry for now · rain likely tomorrow (75%)');
    expect(headline(withNowcast([0, 0]), now: now),
        'No significant rain expected in the next 3 days');
  });
}

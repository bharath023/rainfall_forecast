import 'package:intl/intl.dart';

import 'blend.dart';
import 'models.dart';

/// Rain in a 15-minute step at or above this counts as "raining".
const nowcastRainMm = 0.1;

/// Blended hourly rain at or above this counts as a rainy hour.
const hourlyRainMm = 0.5;

/// A 15-minute step that hasn't finished yet. Open-Meteo stamps each step
/// with its END time, so a step stamped 14:15 covers 14:00–14:15.
class NowcastStep {
  final DateTime start;
  final double mm;
  final int probability;
  const NowcastStep(this.start, this.mm, this.probability);
  bool get isRainy => mm >= nowcastRainMm;
}

List<NowcastStep> upcomingSteps(ForecastData d, DateTime now) {
  return [
    for (var i = 0; i < d.nowcastTime.length; i++)
      if (d.nowcastTime[i].isAfter(now))
        NowcastStep(
          d.nowcastTime[i].subtract(const Duration(minutes: 15)),
          i < d.nowcastMm.length ? d.nowcastMm[i] ?? 0 : 0,
          i < d.nowcastProbability.length
              ? (d.nowcastProbability[i] ?? 0).round()
              : 0,
        ),
  ];
}

/// One plain-language sentence answering "will it rain, and when?", checked
/// from the shortest range (15-min steps) out to the 10-day ensemble.
String headline(ForecastData d, {DateTime? now}) {
  now ??= d.locationNowExact;
  final hm = DateFormat('HH:mm');
  final steps = upcomingSteps(d, now);

  // 1. Next ~3 hours, 15-minute steps.
  if (steps.isNotEmpty) {
    if (steps.first.isRainy) {
      final dry = steps.indexWhere((s) => !s.isRainy);
      return dry < 0
          ? 'Rain for the next few hours'
          : 'Raining now · stopping around ${hm.format(steps[dry].start)}';
    }
    final wet = steps.indexWhere((s) => s.isRainy);
    if (wet >= 0) {
      final minutes = steps[wet].start.difference(now).inMinutes;
      return minutes < 60
          ? 'Rain starting in about ${minutes < 5 ? 5 : (minutes / 5).round() * 5} min'
          : 'Rain likely from ${hm.format(steps[wet].start)}';
    }
  }

  // 2. Next 24 hours, hourly model blend.
  final hourNow = DateTime(now.year, now.month, now.day, now.hour);
  for (var i = 0; i < d.hourlyTime.length; i++) {
    final t = d.hourlyTime[i];
    if (t.isBefore(hourNow) || t.difference(hourNow).inHours > 24) continue;
    final mm = blendAt(d.hourly, i);
    if (mm != null && mm >= hourlyRainMm) {
      final sameDay = t.day == now.day;
      return 'Rain likely ${sameDay ? 'around' : 'tomorrow around'} '
          '${DateFormat('HH:00').format(t)}';
    }
  }

  // 3. Coming days, ensemble probability.
  for (var i = 1; i < d.days.length && i < d.ensembleDaily.length; i++) {
    final p = probability(d.ensembleDaily[i], 1);
    if (p != null && p >= 0.5) {
      final day =
          i == 1 ? 'tomorrow' : 'on ${DateFormat('EEEE').format(d.days[i])}';
      return 'Dry for now · rain likely $day (${(p * 100).round()}%)';
    }
  }
  return 'No significant rain expected in the next ${d.days.length} days';
}

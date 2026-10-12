import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'blend.dart';
import 'models.dart';
import 'summary.dart';

String _mm(double? v) => v == null ? '–' : '${v.toStringAsFixed(1)} mm';
String _pct(double? v) => v == null ? '–' : '${(v * 100).round()}%';

IconData rainIcon(double? mm) {
  if (mm == null) return Icons.help_outline;
  if (mm < 0.2) return Icons.wb_sunny_outlined;
  if (mm < 5) return Icons.grain;
  if (mm < 20) return Icons.water_drop;
  return Icons.thunderstorm;
}

/// Headline card: a plain-language sentence, today's numbers, and the
/// 15-minute rain bars for the next ~3 hours.
class TodayCard extends StatelessWidget {
  final ForecastData data;
  const TodayCard({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final blended = blendAt(data.daily, 0);
    final members =
        data.ensembleDaily.isNotEmpty ? data.ensembleDaily[0] : <double>[];
    final theme = Theme.of(context);
    final now = data.locationNowExact;
    final steps = upcomingSteps(data, now).take(12).toList();
    final nowRainy = steps.isNotEmpty && steps.first.isRainy;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(nowRainy ? Icons.water_drop : rainIcon(blended),
                  size: 40, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(headline(data, now: now),
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
            ]),
            const SizedBox(height: 8),
            Text(
              'Today ${_mm(blended)} · chance ${_pct(probability(members, 1))}'
              ' · models agree: ${agreementLabel(modelSpreadAt(data.daily, 0))}',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (steps.isNotEmpty) ...[
              const SizedBox(height: 16),
              NowcastBars(steps: steps),
            ],
          ],
        ),
      ),
    );
  }
}

/// Bars for each 15-minute step: height = rain amount, with a faint
/// background bar for the chance of rain.
class NowcastBars extends StatelessWidget {
  final List<NowcastStep> steps;
  const NowcastBars({super.key, required this.steps});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Scale so light rain is visible but heavy rain still fits: 2 mm per 15 min
    // (8 mm/h) fills the bar.
    const fullMm = 2.0;
    const barHeight = 56.0;
    final hm = DateFormat('HH:mm');
    final noRain = steps.every((s) => s.mm < nowcastRainMm);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(noRain ? 'Next 3 hours · no rain expected' : 'Next 3 hours',
            style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        SizedBox(
          height: barHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final s in steps)
                Expanded(
                  child: Tooltip(
                    message: '${hm.format(s.start)}: '
                        '${s.mm.toStringAsFixed(1)} mm · ${s.probability}%',
                    child: Stack(
                      alignment: Alignment.bottomCenter,
                      children: [
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          height: barHeight * s.probability / 100,
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          height: s.mm <= 0
                              ? 2
                              : (barHeight * s.mm / fullMm)
                                  .clamp(4.0, barHeight),
                          decoration: BoxDecoration(
                            color: s.mm < nowcastRainMm
                                ? scheme.outlineVariant
                                : scheme.primary,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Now', style: TextStyle(fontSize: 11)),
            if (steps.length > 6)
              Text(hm.format(steps[steps.length ~/ 2].start),
                  style: const TextStyle(fontSize: 11)),
            Text(hm.format(steps.last.start.add(const Duration(minutes: 15))),
                style: const TextStyle(fontSize: 11)),
          ],
        ),
      ],
    );
  }
}

/// Hourly precipitation for the next 72 h, one line per model.
class HourlyChart extends StatelessWidget {
  final ForecastData data;
  const HourlyChart({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final now = data.locationNow;
    var start = data.hourlyTime.indexWhere((t) => !t.isBefore(now));
    if (start < 0) start = 0;
    final end = (start + 72).clamp(0, data.hourlyTime.length);

    var maxY = 1.0;
    final bars = <LineChartBarData>[];
    for (final m in deterministicModels) {
      final s = data.hourly[m.id];
      if (s == null || s.isEmpty) continue;
      final spots = <FlSpot>[];
      for (var i = start; i < end && i < s.length; i++) {
        final v = s[i];
        if (v == null) {
          spots.add(FlSpot.nullSpot);
          continue;
        }
        if (v > maxY) maxY = v;
        spots.add(FlSpot((i - start).toDouble(), v));
      }
      bars.add(LineChartBarData(
        spots: spots,
        color: m.color,
        barWidth: 2,
        dotData: const FlDotData(show: false),
      ));
    }

    final hourFmt = DateFormat('E HH');
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 12),
              child: Text('Next 72 hours · mm per hour',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            SizedBox(
              height: 220,
              child: LineChart(LineChartData(
                minY: 0,
                maxY: maxY * 1.15,
                minX: 0,
                maxX: (end - start - 1).toDouble(),
                lineBarsData: bars,
                gridData: const FlGridData(drawVerticalLine: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      getTitlesWidget: (v, meta) => Text(
                        v.toStringAsFixed(v < 10 ? 1 : 0),
                        style: const TextStyle(fontSize: 10),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 12,
                      reservedSize: 24,
                      getTitlesWidget: (v, meta) {
                        final i = start + v.toInt();
                        if (i >= end) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(hourFmt.format(data.hourlyTime[i]),
                              style: const TextStyle(fontSize: 10)),
                        );
                      },
                    ),
                  ),
                ),
              )),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                for (final m in deterministicModels)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 10, height: 10, color: m.color),
                    const SizedBox(width: 4),
                    Text(m.name, style: const TextStyle(fontSize: 12)),
                  ]),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One day: blended total and probabilities; expands to show every model.
class DayTile extends StatelessWidget {
  final ForecastData data;
  final int index;
  const DayTile({super.key, required this.data, required this.index});

  @override
  Widget build(BuildContext context) {
    final blended = blendAt(data.daily, index);
    final members = index < data.ensembleDaily.length
        ? data.ensembleDaily[index]
        : <double>[];
    final p1 = probability(members, 1);
    final p10 = probability(members, 10);

    return Card(
      child: ExpansionTile(
        leading: Icon(rainIcon(blended)),
        title: Text(DateFormat('EEE d MMM').format(data.days[index])),
        subtitle: Text(p1 == null
            ? 'No ensemble data'
            : 'Rain ${_pct(p1)} · Heavy (≥10 mm) ${_pct(p10)}'),
        trailing: Text(_mm(blended),
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
        children: [
          for (final m in deterministicModels)
            ListTile(
              dense: true,
              leading: CircleAvatar(radius: 6, backgroundColor: m.color),
              title: Text(m.name),
              trailing: Text(_mm(index < (data.daily[m.id]?.length ?? 0)
                  ? data.daily[m.id]![index]
                  : null)),
            ),
          if (members.isNotEmpty)
            ListTile(
              dense: true,
              leading: const Icon(Icons.stacked_line_chart, size: 18),
              title: const Text('Ensemble likely range (10–90%)'),
              subtitle:
                  Text('${members.length} members · ECMWF ENS + NOAA GEFS'),
              trailing: Text(
                  '${percentile(members, 10)!.toStringAsFixed(1)}–${percentile(members, 90)!.toStringAsFixed(1)} mm'),
            ),
        ],
      ),
    );
  }
}

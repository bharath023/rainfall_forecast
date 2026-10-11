import 'dart:math' as math;

import 'models.dart';

/// Weighted multi-model mean at index [i]; models with no data are skipped and
/// the remaining weights re-normalised.
double? blendAt(Map<String, List<double?>> series, int i) {
  var sum = 0.0;
  var weight = 0.0;
  for (final m in deterministicModels) {
    final s = series[m.id];
    if (s == null || i >= s.length || s[i] == null) continue;
    sum += s[i]! * m.weight;
    weight += m.weight;
  }
  return weight == 0 ? null : sum / weight;
}

/// Max minus min across models at index [i] — a quick "do models agree?" signal.
double? modelSpreadAt(Map<String, List<double?>> series, int i) {
  final values = [
    for (final m in deterministicModels)
      if (series[m.id] != null && i < series[m.id]!.length && series[m.id]![i] != null)
        series[m.id]![i]!,
  ];
  if (values.length < 2) return null;
  return values.reduce(math.max) - values.reduce(math.min);
}

/// Fraction of ensemble members with at least [thresholdMm] of rain.
double? probability(List<double> members, double thresholdMm) {
  if (members.isEmpty) return null;
  return members.where((v) => v >= thresholdMm).length / members.length;
}

/// Linear-interpolated percentile (0–100) of ensemble members.
double? percentile(List<double> members, double p) {
  if (members.isEmpty) return null;
  final sorted = [...members]..sort();
  final rank = (p / 100) * (sorted.length - 1);
  final lo = rank.floor();
  final hi = rank.ceil();
  return sorted[lo] + (sorted[hi] - sorted[lo]) * (rank - lo);
}

String agreementLabel(double? spreadMm) {
  if (spreadMm == null) return 'n/a';
  if (spreadMm < 2) return 'High';
  if (spreadMm < 10) return 'Medium';
  return 'Low';
}

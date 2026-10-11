import 'package:flutter_test/flutter_test.dart';
import 'package:rainfall_app/blend.dart';

void main() {
  test('blend skips missing models and re-normalises weights', () {
    final series = <String, List<double?>>{
      'ecmwf_ifs025': [10],
      'gfs_seamless': [0],
      'icon_seamless': [null],
    };
    // (10*1.0 + 0*0.7) / 1.7
    expect(blendAt(series, 0), closeTo(5.88, 0.01));
  });

  test('probability and percentiles from ensemble members', () {
    final members = [0.0, 0.5, 2.0, 12.0];
    expect(probability(members, 1), 0.5);
    expect(probability(members, 10), 0.25);
    expect(percentile(members, 50), closeTo(1.25, 1e-9));
    expect(probability(<double>[], 1), isNull);
  });
}

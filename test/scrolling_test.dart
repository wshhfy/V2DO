import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_app/scrolling.dart';

void main() {
  test('Android fling travels farther while still stopping at content bounds',
      () {
    final metrics = FixedScrollMetrics(
        minScrollExtent: 0,
        maxScrollExtent: 100000,
        pixels: 2000,
        viewportDimension: 800,
        axisDirection: AxisDirection.down,
        devicePixelRatio: 3);
    final standard =
        const ClampingScrollPhysics().createBallisticSimulation(metrics, 1500)!;
    final tuned =
        const ExdoScrollPhysics().createBallisticSimulation(metrics, 1500)!;
    final before = standard.x(10) - 2000;
    final after = tuned.x(10) - 2000;
    expect(after, greaterThan(before * 1.2));
    expect(after, lessThan(before * 2));
    expect(
        const ExdoScrollPhysics()
            .createBallisticSimulation(metrics.copyWith(pixels: 100000), 1500),
        null);
  });
}

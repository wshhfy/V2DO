import 'package:flutter/material.dart';

/// Android edge clamping with a slightly longer fling. iOS keeps native bounce.
class ExdoScrollPhysics extends ClampingScrollPhysics {
  const ExdoScrollPhysics({super.parent});
  @override
  ExdoScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      ExdoScrollPhysics(parent: buildParent(ancestor));
  @override
  Simulation? createBallisticSimulation(
      ScrollMetrics position, double velocity) {
    if (position.outOfRange ||
        velocity.abs() < toleranceFor(position).velocity ||
        (velocity > 0 && position.pixels >= position.maxScrollExtent) ||
        (velocity < 0 && position.pixels <= position.minScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }
    return ClampingScrollSimulation(
        position: position.pixels,
        velocity: velocity,
        friction: .009,
        tolerance: toleranceFor(position));
  }
}

class ExdoScrollBehavior extends MaterialScrollBehavior {
  const ExdoScrollBehavior();
  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      getPlatform(context) == TargetPlatform.iOS
          ? const BouncingScrollPhysics()
          : const ExdoScrollPhysics();
}

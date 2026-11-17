import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Opt-in local measurements, disabled in the distributed APK.
class PerfProbe extends StatefulWidget {
  final Widget child;
  const PerfProbe({required this.child, super.key});
  @override
  State<PerfProbe> createState() => _PerfProbeState();
}

class _PerfProbeState extends State<PerfProbe> {
  final frames = <FrameTiming>[];
  bool scrolling = false;
  Timer? timer;
  void timings(List<FrameTiming> values) {
    if (scrolling) frames.addAll(values);
  }

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(timings);
  }

  @override
  void dispose() {
    timer?.cancel();
    SchedulerBinding.instance.removeTimingsCallback(timings);
    super.dispose();
  }

  void report() {
    scrolling = false;
    if (frames.isEmpty) return;
    final hz = View.of(context).display.refreshRate;
    final budget = 1000000 / hz;
    final build = frames.map((f) => f.buildDuration.inMicroseconds).toList()
      ..sort();
    final raster = frames.map((f) => f.rasterDuration.inMicroseconds).toList()
      ..sort();
    final slow = frames
        .where((f) =>
            f.buildDuration.inMicroseconds > budget ||
            f.rasterDuration.inMicroseconds > budget)
        .length;
    // ignore: avoid_print
    print('EXDO_PERF ${jsonEncode({
          'frames': frames.length,
          'hz': hz,
          'uiP95ms': build[((build.length - 1) * .95).round()] / 1000,
          'rasterP95ms': raster[((raster.length - 1) * .95).round()] / 1000,
          'overBudget': slow
        })}');
    frames.clear();
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.depth != 0) return false;
            if (n is ScrollStartNotification) {
              timer?.cancel();
              scrolling = true;
            }
            if (n is ScrollEndNotification)
              timer = Timer(const Duration(milliseconds: 250), report);
            return false;
          },
          child: Listener(
              onPointerDown: (_) {
                timer?.cancel();
                scrolling = true;
              },
              onPointerUp: (_) {
                timer?.cancel();
                timer = Timer(const Duration(milliseconds: 800), report);
              },
              onPointerCancel: (_) {
                timer?.cancel();
                timer = Timer(const Duration(milliseconds: 800), report);
              },
              child: widget.child));
}

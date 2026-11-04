import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:psu_protocol/psu_protocol.dart';

import '../psu_connection.dart';
import '../theme.dart';

const _windows = <Duration>[
  Duration(seconds: 30),
  Duration(minutes: 2),
  Duration(minutes: 5),
  Duration(minutes: 15),
  Duration(minutes: 30),
];

/// Voltage and current over time, one chart each (same time axis).
class ChartsPanel extends StatefulWidget {
  const ChartsPanel({super.key, required this.connection});

  final PsuConnection connection;

  @override
  State<ChartsPanel> createState() => _ChartsPanelState();
}

class _ChartsPanelState extends State<ChartsPanel> {
  Duration _window = _windows[1];

  @override
  Widget build(BuildContext context) {
    final palette = ChartPalette.of(context);
    final now = DateTime.now();
    final cutoff = now.subtract(_window);
    final history = widget.connection.history;
    var start = _lowerBound(history, cutoff);
    final visible = history.sublist(start);
    final series = _decimate(visible, 600, now);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('History', style: Theme.of(context).textTheme.labelLarge),
                const Spacer(),
                SegmentedButton<Duration>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                  segments: [
                    for (final w in _windows)
                      ButtonSegment(value: w, label: Text(_label(w))),
                  ],
                  selected: {_window},
                  onSelectionChanged: (s) => setState(() => _window = s.first),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _TimeChart(
                title: 'Voltage',
                unit: 'V',
                color: palette.voltage,
                palette: palette,
                spots: series.voltage,
                window: _window,
                showTimeLabels: false,
                decimals: 3,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _TimeChart(
                title: 'Current',
                unit: 'A',
                color: palette.current,
                palette: palette,
                spots: series.current,
                window: _window,
                showTimeLabels: true,
                decimals: 3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _label(Duration d) =>
      d.inMinutes >= 1 ? '${d.inMinutes} min' : '${d.inSeconds} s';

  static int _lowerBound(List<Sample> list, DateTime t) {
    var lo = 0, hi = list.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (list[mid].timestamp.isBefore(t)) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// Reduces [samples] to at most [maxPoints] per series, keeping the min and
  /// max of each bucket so short spikes stay visible. X is seconds before now.
  static ({List<FlSpot> voltage, List<FlSpot> current}) _decimate(
    List<Sample> samples,
    int maxPoints,
    DateTime now,
  ) {
    final voltage = <FlSpot>[];
    final current = <FlSpot>[];
    double x(Sample s) =>
        (s.timestamp.millisecondsSinceEpoch - now.millisecondsSinceEpoch) /
        1000.0;

    if (samples.length <= maxPoints) {
      for (final s in samples) {
        voltage.add(FlSpot(x(s), s.voltage));
        current.add(FlSpot(x(s), s.current));
      }
      return (voltage: voltage, current: current);
    }

    final bucket = (samples.length / (maxPoints / 2)).ceil();
    for (var i = 0; i < samples.length; i += bucket) {
      final end = math.min(i + bucket, samples.length);
      Sample vMin = samples[i],
          vMax = samples[i],
          iMin = samples[i],
          iMax = samples[i];
      for (var j = i + 1; j < end; j++) {
        final s = samples[j];
        if (s.voltage < vMin.voltage) vMin = s;
        if (s.voltage > vMax.voltage) vMax = s;
        if (s.current < iMin.current) iMin = s;
        if (s.current > iMax.current) iMax = s;
      }
      for (final s in [
        vMin,
        vMax,
      ]..sort((a, b) => a.timestamp.compareTo(b.timestamp))) {
        voltage.add(FlSpot(x(s), s.voltage));
      }
      for (final s in [
        iMin,
        iMax,
      ]..sort((a, b) => a.timestamp.compareTo(b.timestamp))) {
        current.add(FlSpot(x(s), s.current));
      }
    }
    return (voltage: voltage, current: current);
  }
}

class _TimeChart extends StatelessWidget {
  const _TimeChart({
    required this.title,
    required this.unit,
    required this.color,
    required this.palette,
    required this.spots,
    required this.window,
    required this.showTimeLabels,
    required this.decimals,
  });

  final String title;
  final String unit;
  final Color color;
  final ChartPalette palette;
  final List<FlSpot> spots;
  final Duration window;
  final bool showTimeLabels;
  final int decimals;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.bodySmall?.copyWith(
      color: palette.muted,
      fontFeatures: tabularFigures,
    );
    final maxY = _niceMax(
      spots.isEmpty ? 0 : spots.map((s) => s.y).reduce(math.max),
    );
    final windowSec = window.inSeconds.toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text('$title ($unit)', style: theme.textTheme.labelMedium),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: LineChart(
            duration: Duration.zero,
            LineChartData(
              minX: -windowSec,
              maxX: 0,
              minY: 0,
              maxY: maxY,
              clipData: const FlClipData.all(),
              backgroundColor: palette.surface,
              gridData: FlGridData(
                drawVerticalLine: true,
                horizontalInterval: maxY / 4,
                verticalInterval: windowSec / 6,
                getDrawingHorizontalLine: (_) =>
                    FlLine(color: palette.grid, strokeWidth: 1),
                getDrawingVerticalLine: (_) =>
                    FlLine(color: palette.grid, strokeWidth: 1),
              ),
              borderData: FlBorderData(
                show: true,
                border: Border(
                  bottom: BorderSide(color: palette.axis),
                  left: BorderSide(color: palette.axis),
                ),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 52,
                    interval: maxY / 4,
                    getTitlesWidget: (v, meta) => SideTitleWidget(
                      meta: meta,
                      child: Text(
                        v.toStringAsFixed(maxY < 2 ? 2 : (maxY < 10 ? 1 : 0)),
                        style: labelStyle,
                      ),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: showTimeLabels,
                    reservedSize: 24,
                    interval: windowSec / 6,
                    getTitlesWidget: (v, meta) => SideTitleWidget(
                      meta: meta,
                      child: Text(_timeLabel(v), style: labelStyle),
                    ),
                  ),
                ),
              ),
              lineTouchData: LineTouchData(
                handleBuiltInTouches: true,
                getTouchedSpotIndicator: (bar, indexes) => [
                  for (final _ in indexes)
                    TouchedSpotIndicatorData(
                      FlLine(
                        color: palette.muted,
                        strokeWidth: 1,
                        dashArray: [4, 4],
                      ),
                      FlDotData(
                        getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                          radius: 4,
                          color: color,
                          strokeWidth: 2,
                          strokeColor: palette.surface,
                        ),
                      ),
                    ),
                ],
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => theme.colorScheme.inverseSurface,
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  getTooltipItems: (touched) => [
                    for (final t in touched)
                      LineTooltipItem(
                        '${t.y.toStringAsFixed(decimals)} $unit\n',
                        theme.textTheme.bodyMedium!.copyWith(
                          color: theme.colorScheme.onInverseSurface,
                          fontWeight: FontWeight.w600,
                          fontFeatures: tabularFigures,
                        ),
                        children: [
                          TextSpan(
                            text: _timeLabel(t.x, precise: true),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onInverseSurface,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  color: color,
                  barWidth: 2,
                  isCurved: false,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    color: color.withValues(alpha: 0.08),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Rounds a value up to a "nice" axis maximum so the grid stays readable.
  static double _niceMax(double v) {
    if (v <= 0) return 1;
    final padded = v * 1.1;
    final exp = math.pow(10, (math.log(padded) / math.ln10).floor()).toDouble();
    final f = padded / exp;
    final nice = f <= 1
        ? 1.0
        : f <= 2
        ? 2.0
        : f <= 2.5
        ? 2.5
        : f <= 5
        ? 5.0
        : 10.0;
    return nice * exp;
  }

  /// Axis labels use one format per window: seconds below two minutes,
  /// otherwise m:ss, so neighbouring labels never mix units.
  String _timeLabel(double secondsBeforeNow, {bool precise = false}) {
    final s = -secondsBeforeNow;
    if (precise) return '${s.toStringAsFixed(1)} s ago';
    if (s < 0.5) return 'now';
    if (window.inSeconds < 120) return '-${s.round()} s';
    final total = s.round();
    return '-${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
  }
}

// lib/ui/dashboard/trend_chart_view.dart
// Draws a TrendChart (core/models/trend_chart.dart) as rows of bars: one
// row per x label, one bar per series, the value beside it. A reference
// line (e.g. the done threshold) is drawn across every row. Theme colours only.
import 'package:flutter/material.dart';

import '../../core/models/trend_chart.dart';

class TrendChartView extends StatelessWidget {
  final TrendChart chart;

  /// Values are shares (0–1) shown as percents.
  final bool percent;

  const TrendChartView({super.key, required this.chart, this.percent = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final palette = [colors.primary, colors.tertiary, colors.secondary, colors.error, colors.outline, colors.inversePrimary];
    if (chart.isEmpty) {
      return Text('No data yet for ${chart.title}.', style: TextStyle(color: colors.onSurfaceVariant));
    }
    final values = [for (final s in chart.series) ...s.values.whereType<num>()];
    final maxValue = [
      if (percent) 1.0,
      ...values.map((v) => v.toDouble()),
      ?chart.referenceLine,
    ].fold<double>(0, (a, b) => b > a ? b : a);
    String fmt(num? v) => v == null ? '—' : percent ? '${(v * 100).toStringAsFixed(1)}%' : _num(v);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(chart.title, style: theme.textTheme.titleSmall),
        const SizedBox(height: 6),
        if (chart.series.length > 1)
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              for (var i = 0; i < chart.series.length; i++)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 10, height: 10, color: palette[i % palette.length]),
                  const SizedBox(width: 4),
                  Text(chart.series[i].name, style: theme.textTheme.bodySmall),
                ]),
            ],
          ),
        if (chart.referenceLine != null)
          Text('Line: ${fmt(chart.referenceLine)}', style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
        const SizedBox(height: 6),
        for (var x = 0; x < chart.xLabels.length; x++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 110, child: Text(chart.xLabels[x], style: theme.textTheme.bodySmall)),
                Expanded(
                  child: Column(
                    children: [
                      for (var i = 0; i < chart.series.length; i++)
                        _Bar(
                          value: x < chart.series[i].values.length ? chart.series[i].values[x] : null,
                          max: maxValue,
                          reference: chart.referenceLine,
                          color: palette[i % palette.length],
                          label: fmt(x < chart.series[i].values.length ? chart.series[i].values[x] : null),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

String _num(num v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

class _Bar extends StatelessWidget {
  final num? value;
  final double max;
  final double? reference;
  final Color color;
  final String label;
  const _Bar({required this.value, required this.max, required this.reference, required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                final share = max <= 0 || value == null ? 0.0 : (value!.toDouble() / max).clamp(0.0, 1.0);
                return Stack(
                  children: [
                    Container(height: 12, decoration: BoxDecoration(color: colors.surfaceContainerHighest, borderRadius: BorderRadius.circular(3))),
                    Container(
                      height: 12,
                      width: c.maxWidth * share,
                      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
                    ),
                    if (reference != null && max > 0)
                      Positioned(
                        left: (c.maxWidth * (reference! / max).clamp(0.0, 1.0)) - 1,
                        child: Container(width: 2, height: 12, color: colors.onSurface),
                      ),
                  ],
                );
              },
            ),
          ),
          SizedBox(width: 64, child: Text(label, textAlign: TextAlign.right, style: Theme.of(context).textTheme.bodySmall)),
        ],
      ),
    );
  }
}

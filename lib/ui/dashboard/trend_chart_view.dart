// lib/ui/dashboard/trend_chart_view.dart
// Draws a TrendChart (core/models/trend_chart.dart) as rows of bars: one
// row per x label, one bar per series, the value beside it. A reference
// line (e.g. the done threshold) is drawn across every row. Theme colours only.
import 'package:flutter/material.dart';

import '../../core/models/trend_chart.dart';
import '../common/screen_kit.dart';
import '../theme/basa_theme.dart';

class TrendChartView extends StatelessWidget {
  final TrendChart chart;

  /// Values are shares (0–1) shown as percents.
  final bool percent;

  /// Shown beside the title.
  final IconData? icon;

  const TrendChartView({super.key, required this.chart, this.percent = false, this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final palette = [colors.primary, colors.tertiary, colors.secondary, colors.error, colors.outline, colors.inversePrimary];
    if (chart.isEmpty) {
      return Row(children: [
        IconBadge(icon ?? Icons.insights_outlined,
            size: 34, background: colors.surfaceContainerHigh, foreground: colors.onSurfaceVariant),
        const SizedBox(width: 12),
        Expanded(child: Text('No data yet for ${chart.title}.', style: TextStyle(color: colors.onSurfaceVariant))),
      ]);
    }
    final labelWidth = MediaQuery.sizeOf(context).width < 400 ? 80.0 : 110.0;
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
        Row(children: [
          if (icon != null) ...[IconBadge(icon!, size: 34), const SizedBox(width: 12)],
          Expanded(child: Text(chart.title, style: theme.textTheme.titleMedium)),
        ]),
        const SizedBox(height: 10),
        if (chart.series.length > 1)
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              for (var i = 0; i < chart.series.length; i++)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: palette[i % palette.length], shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Text(chart.series[i].name, style: theme.textTheme.bodySmall),
                ]),
            ],
          ),
        if (chart.referenceLine != null)
          Text('Line: ${fmt(chart.referenceLine)}', style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
        const SizedBox(height: 8),
        for (var x = 0; x < chart.xLabels.length; x++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: labelWidth, child: Text(chart.xLabels[x], style: theme.textTheme.bodySmall)),
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
                final radius = BorderRadius.circular(BasaRadius.small / 2);
                return SizedBox(
                  height: 18,
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      Container(height: 14, decoration: BoxDecoration(color: colors.surfaceContainerHighest, borderRadius: radius)),
                      Container(
                        height: 14,
                        width: c.maxWidth * share,
                        decoration: BoxDecoration(color: color, borderRadius: radius),
                      ),
                      // The reference line, a little taller than the bar.
                      if (reference != null && max > 0)
                        Positioned(
                          top: 0,
                          bottom: 0,
                          left: (c.maxWidth * (reference! / max).clamp(0.0, 1.0)) - 1,
                          child: Container(
                            width: 2,
                            decoration: BoxDecoration(color: colors.onSurface, borderRadius: BorderRadius.circular(1)),
                          ),
                        ),
                    ],
                  ),
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

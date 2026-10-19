// lib/core/models/trend_chart.dart
//
// Chart data for the dashboard trends (D4-D5). Pure Dart, no chart library:
// the UI draws it. One value per x label in every series; null = a gap (the
// point does not exist, e.g. a round the school does not hold).

class TrendSeries {
  final String name;
  final List<num?> values;

  const TrendSeries(this.name, this.values);
}

class TrendChart {
  final String title;
  final List<String> xLabels;
  final List<TrendSeries> series;
  final double? referenceLine; // e.g. the done threshold, in the values' unit

  const TrendChart(this.title, this.xLabels, this.series, {this.referenceLine});

  /// No point at all (no x label, or every value null).
  bool get isEmpty => xLabels.isEmpty || series.every((s) => s.values.every((v) => v == null));
}

/// What a trend covers: one section, one school, or every school on this
/// device (the region; superadmin only).
sealed class TrendScope {
  const TrendScope();

  /// `section:ID`, `school:ID` or `region`.
  static TrendScope parse(String raw) {
    final s = raw.trim().toLowerCase();
    if (s == 'region') return const RegionScope();
    final colon = s.indexOf(':');
    final id = colon < 0 ? null : int.tryParse(s.substring(colon + 1));
    if (id != null && id > 0) {
      switch (s.substring(0, colon)) {
        case 'section':
          return SectionScope(id);
        case 'school':
          return SchoolScope(id);
      }
    }
    throw FormatException('A scope is section:ID, school:ID or region (got "$raw").');
  }
}

class SectionScope extends TrendScope {
  final int sectionId;
  const SectionScope(this.sectionId);
}

class SchoolScope extends TrendScope {
  final int schoolId;
  const SchoolScope(this.schoolId);
}

class RegionScope extends TrendScope {
  const RegionScope();
}

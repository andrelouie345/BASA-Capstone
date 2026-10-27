// lib/ui/admin/threshold_fields.dart
// Asks for new threshold values (CRLA, Phil-IRI) and returns only the ones
// that changed, typed like the current value (whole number, decimal,
// true/false, or a comma list of whole numbers). Admin build only.
import 'package:flutter/material.dart';

import '../common/screen_kit.dart';
import '../crla/crla_thresholds_screen.dart';

/// Changed keys and their typed values; null when cancelled or a value is invalid.
Future<Map<String, Object?>?> askThresholdChanges(BuildContext context,
    {required String title, required Map<String, Object?> current}) async {
  String show(Object? v) => v is List ? v.join(', ') : '$v';
  final f = await askFields(
    context,
    title: title,
    note: 'Numbers; true/false for yes/no rows; comma lists for lists. Only changed values are saved.',
    fields: [for (final e in current.entries) FieldSpec(e.key, thresholdLabel(e.key), initial: show(e.value))],
  );
  if (f == null || !context.mounted) return null;
  final changes = <String, Object?>{};
  for (final e in f.entries) {
    final old = current[e.key];
    if (e.value == show(old)) continue;
    final Object? v = switch (old) {
      bool _ => switch (e.value.toLowerCase()) {
        'true' => true,
        'false' => false,
        _ => null,
      },
      int _ => int.tryParse(e.value),
      double _ => double.tryParse(e.value),
      List _ => _intList(e.value),
      _ => e.value,
    };
    if (v == null) {
      showNote(context, '${thresholdLabel(e.key)}: "${e.value}" is not a valid value.');
      return null;
    }
    changes[e.key] = v;
  }
  return changes;
}

List<int>? _intList(String text) {
  final parts = text.split(',').map((x) => int.tryParse(x.trim())).toList();
  return parts.contains(null) ? null : parts.cast<int>();
}

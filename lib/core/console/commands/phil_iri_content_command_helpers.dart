// lib/core/console/commands/phil_iri_content_command_helpers.dart
// Helpers shared by phil_iri_content_commands.dart and phil_iri_content_admin_commands.dart (no admin code here).

import '../../models/phil_iri_collection.dart';
import '../../models/phil_iri_passage.dart';

/// A bad argument: the handler returns the message as-is.
class PhilIriContentUsage implements Exception {
  final String message;
  const PhilIriContentUsage(this.message);
}

int philIriContentInt(String raw, String name) =>
    int.tryParse(raw) ?? (throw PhilIriContentUsage('Invalid $name: "$raw" (expected a number)'));

String philIriContentCollectionLine(PhilIriCollection c) => [
      '[${c.id}] ${c.name}',
      c.schoolId == null ? 'region-wide' : 'school ${c.schoolId}',
      if (c.isPrescribed) 'prescribed',
      c.isGradeLeveled ? 'graded' : 'ungraded',
      c.hasComprehension ? 'comprehension' : 'no comprehension',
      if (c.readingOrder != null) 'order ${c.readingOrder!.join(',')}',
      if (!c.isActive) 'INACTIVE',
    ].join(' · ');

String philIriContentPassageLine(PhilIriPassage p) => [
      '[${p.id}] ${p.title}',
      'collection ${p.collectionId}',
      if (p.level != null) 'Grade ${p.level}',
      if (p.testType != null) p.testType!,
      if (p.setCode != null) 'set ${p.setCode}',
      if (p.selectionNo != null) 'selection ${p.selectionNo}',
      '${p.wordCount} words',
      if (!p.isActive) 'INACTIVE',
    ].join(' · ');

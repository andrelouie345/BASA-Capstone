// lib/core/models/crla_language.dart

/// Canonical language name used in crla_stories and crla_assessments.
/// Source files and the live scoresheet say "Filipino"; the DB stores "Tagalog".
String normalizeCrlaLanguage(String language) {
  final trimmed = language.trim();
  if (trimmed.toLowerCase() == 'filipino') return 'Tagalog';
  return trimmed;
}
// lib/core/models/phil_iri_miscue.dart
//
// One miscue the tutor marked while the learner read a passage aloud. Raw
// miscues are kept (not just totals) so scores can always be regenerated and
// miscue types can be analysed.

/// The 7 miscue types of the 2018 manual (Table 4). All of them count toward
/// the word reading score; a self-correction is a flag on a miscue, not a type.
enum PhilIriMiscueType {
  mispronunciation('Mispronunciation'),
  omission('Omission'),
  substitution('Substitution'),
  insertion('Insertion'),
  repetition('Repetition'),
  transposition('Transposition'),
  reversal('Reversal');

  final String label;
  const PhilIriMiscueType(this.label);

  static PhilIriMiscueType fromString(String value) {
    return PhilIriMiscueType.values.firstWhere(
      (t) => t.name == value || t.label == value,
      orElse: () => throw ArgumentError('Invalid PhilIriMiscueType value: $value'),
    );
  }
}

class PhilIriMiscue {
  final int? id;
  final int readingId;          // the passage reading this belongs to
  /// Position in PhilIriPassage.words (0-based). For an insertion it is the
  /// word the inserted text comes BEFORE (words.length = after the last word).
  /// Transposition/reversal: the first of the words involved.
  final int wordIndex;
  final PhilIriMiscueType type;
  final String? spokenText;     // what the learner said / inserted, optional
  final bool selfCorrected;     // marked "S": recorded but not counted

  PhilIriMiscue({
    this.id,
    required this.readingId,
    required this.wordIndex,
    required this.type,
    this.spokenText,
    this.selfCorrected = false,
  });

  bool get counts => !selfCorrected;

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'reading_id': readingId,
        'word_index': wordIndex,
        'miscue_type': type.name,
        'spoken_text': spokenText,
        'self_corrected': selfCorrected,
      };

  factory PhilIriMiscue.fromMap(Map<String, Object?> m) => PhilIriMiscue(
        id: m['id'] as int?,
        readingId: m['reading_id'] as int,
        wordIndex: m['word_index'] as int,
        type: PhilIriMiscueType.fromString(m['miscue_type'] as String),
        spokenText: m['spoken_text'] as String?,
        selfCorrected: m['self_corrected'] is bool
            ? m['self_corrected'] as bool
            : (m['self_corrected'] as int? ?? 0) == 1,
      );
}

/// Miscues that count toward the word reading score.
int philIriCountedMiscues(Iterable<PhilIriMiscue> miscues) =>
    miscues.where((m) => m.counts).length;

/// Counted miscues per type (Form 3 Part B), every type present with 0 default.
Map<PhilIriMiscueType, int> philIriMiscueSummary(Iterable<PhilIriMiscue> miscues) {
  final summary = {for (final t in PhilIriMiscueType.values) t: 0};
  for (final m in miscues.where((m) => m.counts)) {
    summary[m.type] = summary[m.type]! + 1;
  }
  return summary;
}

// lib/core/models/crla_variant.dart
// The CRLA subject variants a learner can be assessed in, and the language
// each implies (mother tongue has none: the tutor names it, e.g. Cebuano).
const crlaSubjectVariants = ['mt', 'fil', 'eng'];

/// fil -> Tagalog, eng -> English; null for mt (and anything else).
String? crlaDefaultLanguage(String variant) => switch (variant) {
      'fil' => 'Tagalog',
      'eng' => 'English',
      _ => null,
    };

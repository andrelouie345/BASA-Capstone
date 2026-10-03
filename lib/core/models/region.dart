// lib/core/models/region.dart

class Region {
  final int id;
  final String code;
  final String name;

  const Region({required this.id, required this.code, required this.name});

  @override
  String toString() => '$code ($name)';

  static const List<Region> all = [
    Region(id: 1, code: 'Region I', name: 'Ilocos Region'),
    Region(id: 2, code: 'Region II', name: 'Cagayan Valley'),
    Region(id: 3, code: 'Region III', name: 'Central Luzon'),
    Region(id: 4, code: 'Region IV-A', name: 'CALABARZON'),
    Region(id: 5, code: 'Region IV-B', name: 'MIMAROPA'),
    Region(id: 6, code: 'Region V', name: 'Bicol Region'),
    Region(id: 7, code: 'NCR', name: 'National Capital Region'),
    Region(id: 8, code: 'CAR', name: 'Cordillera Administrative Region'),
    Region(id: 9, code: 'Region VI', name: 'Western Visayas'),
    Region(id: 10, code: 'Region VII', name: 'Central Visayas'),
    Region(id: 11, code: 'Region VIII', name: 'Eastern Visayas'),
    Region(id: 12, code: 'Region IX', name: 'Zamboanga Peninsula'),
    Region(id: 13, code: 'Region X', name: 'Northern Mindanao'),
    Region(id: 14, code: 'Region XI', name: 'Davao Region'),
    Region(id: 15, code: 'Region XII', name: 'SOCCSKSARGEN'),
    Region(id: 16, code: 'Region XIII', name: 'Caraga'),
    Region(id: 17, code: 'BARMM', name: 'Bangsamoro Autonomous Region in Muslim Mindanao'),
    Region(id: 18, code: 'NIR', name: 'Negros Island Region'),
  ];

  static Region? byId(int id) {
    for (final r in all) {
      if (r.id == id) return r;
    }
    return null;
  }

  // Full names and known aliases — checked first, against the whole
  // normalized string (lowercase, collapsed whitespace, stripped punctuation).
  static const Map<String, int> _aliases = {
    'ilocos region': 1,
    'cagayan valley': 2,
    'central luzon': 3,
    'calabarzon': 4,
    'mimaropa': 5,
    'bicol region': 6,
    'ncr': 7,
    'national capital region': 7,
    'metro manila': 7, // common alias
    'car': 8,
    'cordillera administrative region': 8,
    'cordillera': 8,
    'western visayas': 9,
    'central visayas': 10,
    'eastern visayas': 11,
    'zamboanga peninsula': 12,
    'northern mindanao': 13,
    'davao region': 14,
    'soccsksargen': 15,
    'caraga': 16,
    'barmm': 17,
    'bangsamoro autonomous region in muslim mindanao': 17,
    'armm': 17, // historical pre-2019 name
    'autonomous region in muslim mindanao': 17,
    'nir': 18,
    'negros island region': 18,
  };

  // Compact numeral/roman-numeral tokens, AFTER stripping a leading
  // "region" word and all whitespace/hyphens/punctuation. Covers
  // "Region X", "RegionX", "Region 10", "Region10", "X", "10", and the
  // IV-A/IV-B variants ("Region IV-A", "4a", "iv-a", ...).
  // Bare "4"/"iv" (no A/B) defaults to IV-A per Ethan's decision.
  static const Map<String, int> _numerals = {
    'i': 1, '1': 1,
    'ii': 2, '2': 2,
    'iii': 3, '3': 3,
    'iv': 4, '4': 4, 'iva': 4, '4a': 4,
    'ivb': 5, '4b': 5,
    'v': 6, '5': 6,
    'vi': 9, '6': 9,
    'vii': 10, '7': 10,
    'viii': 11, '8': 11,
    'ix': 12, '9': 12,
    'x': 13, '10': 13,
    'xi': 14, '11': 14,
    'xii': 15, '12': 15,
    'xiii': 16, '13': 16,
  };

  /// Returns the matching region id, or null if nothing matched.
  /// Does not throw — callers decide what "unmatched" means for them.
  static int? resolve(String? raw) {
    if (raw == null) return null;
    final normalized = raw
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s-]'), '') // strip punctuation
        .replaceAll(RegExp(r'\s+'), ' ')      // collapse whitespace
        .trim();
    if (normalized.isEmpty) return null;

    if (_aliases.containsKey(normalized)) return _aliases[normalized];

    final withoutRegionWord = normalized.replaceFirst(RegExp(r'^region\s*'), '');
    final compact = withoutRegionWord.replaceAll(RegExp(r'[^a-z0-9]'), '');
    return _numerals[compact];
  }
}
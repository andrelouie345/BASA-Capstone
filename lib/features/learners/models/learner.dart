class Learner {
  final String id;
  final String name;
  final String lrn;
  final String grade;
  final String section;
  final String crla;
  final String philIri;
  final String aralStatus;
  final String gain;
  final String lastAssessed;

  const Learner({
    required this.id,
    required this.name,
    required this.lrn,
    required this.grade,
    required this.section,
    required this.crla,
    required this.philIri,
    required this.aralStatus,
    required this.gain,
    required this.lastAssessed,
  });

  String get initials {
    final parts = name.split(' ');
    if (parts.length >= 2) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }
}

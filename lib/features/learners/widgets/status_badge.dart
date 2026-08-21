import 'package:flutter/material.dart';

class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    required this.type,
  });

  final String label;
  final BadgeType type;

  @override
  Widget build(BuildContext context) {
    final (backgroundColor, textColor) = _getColors();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }

  (Color, Color) _getColors() {
    return switch (type) {
      BadgeType.crlaNonReader => (const Color(0xFFFEE4E8), const Color(0xFFD84C66)),
      BadgeType.crlaLow => (const Color(0xFFFFF4E6), const Color(0xFFE8912B)),
      BadgeType.crlaAverage => (const Color(0xFFEEF5FF), const Color(0xFF1F67D6)),
      BadgeType.crlaProficient => (const Color(0xFFEDFBF5), const Color(0xFF1D8F5D)),
      BadgeType.philIriFrustration => (const Color(0xFFFEE4E8), const Color(0xFFD84C66)),
      BadgeType.philIriInstructional => (const Color(0xFFFFF4E6), const Color(0xFFE8912B)),
      BadgeType.philIriIndependent => (const Color(0xFFEDFBF5), const Color(0xFF1D8F5D)),
      BadgeType.aralActive => (const Color(0xFFEEF5FF), const Color(0xFF1F67D6)),
      BadgeType.aralNotEnrolled => (const Color(0xFFF0F4FA), const Color(0xFF7D91B2)),
      BadgeType.aralPending => (const Color(0xFFFFF4E6), const Color(0xFFE8912B)),
      BadgeType.aralCompleted => (const Color(0xFFEDFBF5), const Color(0xFF1D8F5D)),
    };
  }

  static StatusBadge crla(String crlaStatus) {
    final type = switch (crlaStatus) {
      'Non-Reader' => BadgeType.crlaNonReader,
      'Low' => BadgeType.crlaLow,
      'Average' => BadgeType.crlaAverage,
      'Proficient' => BadgeType.crlaProficient,
      _ => BadgeType.crlaLow,
    };
    return StatusBadge(label: crlaStatus, type: type);
  }

  static StatusBadge philIri(String status) {
    final type = switch (status) {
      'Frustration' => BadgeType.philIriFrustration,
      'Instructional' => BadgeType.philIriInstructional,
      'Independent' => BadgeType.philIriIndependent,
      _ => BadgeType.philIriFrustration,
    };
    return StatusBadge(label: status, type: type);
  }

  static StatusBadge aralStatus(String status) {
    final type = switch (status) {
      'Active' => BadgeType.aralActive,
      'Not Enrolled' => BadgeType.aralNotEnrolled,
      'Pending' => BadgeType.aralPending,
      'Completed' => BadgeType.aralCompleted,
      _ => BadgeType.aralNotEnrolled,
    };
    return StatusBadge(label: status, type: type);
  }
}

enum BadgeType {
  crlaNonReader,
  crlaLow,
  crlaAverage,
  crlaProficient,
  philIriFrustration,
  philIriInstructional,
  philIriIndependent,
  aralActive,
  aralNotEnrolled,
  aralPending,
  aralCompleted,
}

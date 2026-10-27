// lib/ui/aral/aral_common.dart
// Small pieces the ARAL screens share: a learner's program label, the
// school year picker row, and the user's school.
import 'package:flutter/material.dart';

import '../../core/models/aral_enrollment.dart';
import '../common/screen_kit.dart';

/// "KS2 Basic", "Foundational", ...
String aralProgramLabel(AralEnrollment e) => e.track == null ? e.keyStage.label : '${e.keyStage.label} ${e.track!.label}';

/// "active" or "exited (reason)".
String aralStatusLabel(AralEnrollment e) =>
    e.status == AralStatus.active ? 'active' : 'exited${e.exitReason == null ? '' : ' (${e.exitReason!.value.replaceAll('_', ' ')})'}';

/// The signed-in user's school; null for a superadmin.
int? mySchoolId(BuildContext context) => vmsOf(context).auth.currentUser?.schoolId;

/// Shown where a screen needs a school and the user has none (superadmin).
class NeedsSchoolNote extends StatelessWidget {
  const NeedsSchoolNote({super.key});

  @override
  Widget build(BuildContext context) =>
      const EmptyNote('This screen works on one school. Sign in with a school account to use it.', icon: Icons.school_outlined);
}

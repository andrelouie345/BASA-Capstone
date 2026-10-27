// lib/ui/common/signed_in_user.dart
// Who is signed in: name, role and school (docs/handoff/screens/common.md,
// Signed-in user). Getters only, except the school's name, which needs the
// server: offline, the card shows the school's number instead.
import 'package:flutter/material.dart';

import '../../core/models/school.dart';
import '../../core/models/user.dart';
import '../../core/models/user_role.dart';
import '../basa_scope.dart';

/// Superadmin = admin with no school (regional).
bool isSuperadmin(User u) => u.role == UserRole.admin && u.schoolId == null;

/// Admins and coordinators have the same permissions.
bool isAdminOrCoordinator(User u) => u.role == UserRole.admin || u.role == UserRole.coordinator;

String roleLabel(User u) => switch (u.role) {
  UserRole.admin => u.schoolId == null ? 'Superadmin' : 'Admin',
  UserRole.coordinator => 'Coordinator',
  UserRole.tutor => 'Tutor',
};

/// Up to two initials from the full name (or the email when the name is empty).
String initialsOf(User u) {
  final words = u.fullName.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return u.email.isEmpty ? '?' : u.email[0].toUpperCase();
  final first = words.first[0];
  final last = words.length > 1 ? words.last[0] : '';
  return (first + last).toUpperCase();
}

class UserAvatar extends StatelessWidget {
  final User user;
  final double radius;
  const UserAvatar({super.key, required this.user, this.radius = 20});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: radius,
      backgroundColor: colors.primaryContainer,
      foregroundColor: colors.onPrimaryContainer,
      child: Text(
        initialsOf(user),
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: radius * 0.75),
      ),
    );
  }
}

/// Name, role and school of the signed-in user; nothing when nobody is.
class SignedInUserTile extends StatefulWidget {
  /// Also show the email.
  final bool showEmail;
  final VoidCallback? onTap;
  const SignedInUserTile({super.key, this.showEmail = true, this.onTap});

  @override
  State<SignedInUserTile> createState() => _SignedInUserTileState();
}

class _SignedInUserTileState extends State<SignedInUserTile> {
  String? _schoolName;
  int? _loadedFor;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadSchool();
  }

  Future<void> _loadSchool() async {
    final vms = BasaScope.of(context);
    final user = vms.auth.currentUser;
    final id = user?.schoolId;
    if (id == null || vms.auth.isOffline || _loadedFor == id) return;
    _loadedFor = id;
    String? nameIn(List<School> items) => items.where((s) => s.id == id).firstOrNull?.schoolName;
    final schools = vms.school;
    if (schools.items.isNotEmpty) {
      // Already loaded: no await, so this runs before the build (no setState).
      _schoolName = nameIn(schools.items);
      return;
    }
    try {
      await schools.loadAll();
      if (mounted) setState(() => _schoolName = nameIn(schools.items));
    } catch (e) {
      // The name is a nicety: keep the number, log why.
      debugPrint('SignedInUserTile: school name: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = BasaScope.of(context).auth.currentUser;
    if (user == null) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final place = user.schoolId == null ? 'All schools (regional)' : (_schoolName ?? 'School #${user.schoolId}');
    return ListTile(
      onTap: widget.onTap,
      leading: UserAvatar(user: user),
      title: Text(user.fullName.isEmpty ? user.email : user.fullName, style: text.titleSmall),
      subtitle: Text(
        [roleLabel(user), place, if (widget.showEmail) user.email].join(' · '),
        style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

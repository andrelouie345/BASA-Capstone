// lib/ui/admin/users_screen.dart
// Users (docs/handoff/screens/admin.md, Users): the accounts this admin may
// see, a new account (its temporary password is shown once), and turning an
// account on or off. Admin build only.
import 'package:flutter/material.dart';

import '../../core/models/school.dart';
import '../../core/models/user.dart';
import '../../core/models/user_role.dart';
import '../common/pickers.dart';
import '../common/screen_kit.dart';
import '../common/signed_in_user.dart';
import 'admin_scope.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  int _reload = 0;
  String _filter = '';

  /// Only this role; null = all.
  UserRole? _role;

  Future<void> _create() async {
    final users = AdminScope.of(context).users;
    final r = await showDialog<_NewUser>(context: context, builder: (_) => const _NewUserDialog());
    if (r == null || !mounted) return;
    final password = await runAction(
      context,
      () => users.create(email: r.email, fullName: r.fullName, role: r.role, schoolId: r.schoolId),
      where: 'UsersScreen',
    );
    if (!mounted) return;
    setState(() => _reload++);
    if (password == null && users.lastMirrorWarning == null) return;
    await showTextDialog(
      context,
      title: 'Account created',
      text: [
        if (password != null)
          'Temporary password for ${r.email}:\n\n$password\n\nIt is shown only once. They must change it at '
              'their first sign-in.',
        if (users.lastMirrorWarning != null) 'Warning: ${users.lastMirrorWarning}',
      ].join('\n\n'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final users = AdminScope.of(context).users;
    final wide = isWideScreen(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Users'),
        actions: [
          if (wide) mainActionButton(onPressed: _create, icon: Icons.person_add_alt_1, label: 'New account'),
        ],
      ),
      floatingActionButton:
          wide ? null : mainActionFab(onPressed: _create, icon: Icons.person_add_alt_1, label: 'New account'),
      body: LoadView<List<User>>(
        where: 'UsersScreen',
        reloadKey: _reload,
        load: (_) async {
          await users.loadAll();
          return users.items;
        },
        builder: (context, items, reload) {
          final q = _filter.toLowerCase();
          final shown = items
              .where((u) => _role == null || u.role == _role)
              .where((u) => q.isEmpty || u.email.toLowerCase().contains(q) || u.fullName.toLowerCase().contains(q))
              .toList();
          final active = items.where((u) => u.isActive).length;
          return PageBody(
            children: [
              StatGrid(tileWidth: 170, tiles: [
                StatTile(label: 'Accounts', value: '${items.length}', icon: Icons.manage_accounts_outlined),
                StatTile(label: 'Active', value: '$active', icon: Icons.check_circle_outline),
                StatTile(label: 'Turned off', value: '${items.length - active}', icon: Icons.block),
                StatTile(
                  label: 'Tutors',
                  value: '${items.where((u) => u.role == UserRole.tutor).length}',
                  icon: Icons.school_outlined,
                ),
              ]),
              FilterBar(children: [
                TextField(
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Search name or email'),
                  onChanged: (v) => setState(() => _filter = v),
                ),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final r in <UserRole?>[null, ...UserRole.values])
                    ChoiceChip(
                      label: Text(r == null ? 'All' : _roleName(r)),
                      selected: _role == r,
                      onSelected: (_) => setState(() => _role = r),
                    ),
                ]),
              ]),
              if (shown.isEmpty)
                const EmptyNote('No accounts match.', icon: Icons.person_search_outlined)
              else
                ListCard(
                  children: [
                    for (final u in shown)
                      ListRow(
                        leading: UserAvatar(user: u),
                        title: u.fullName.isEmpty ? u.email : u.fullName,
                        subtitle: '${roleLabel(u)} · ${u.email}${u.schoolId == null ? '' : ' · school #${u.schoolId}'}',
                        trailing: [
                          StatusChip(u.isActive ? 'Active' : 'Off', tone: u.isActive ? StatusTone.good : StatusTone.neutral),
                          Switch(
                            value: u.isActive,
                            onChanged: (on) async {
                              await runAction(context, () => users.setActive(u.id, on),
                                  done: on ? 'Account turned on.' : 'Account turned off.', where: 'UsersScreen');
                              reload();
                            },
                          ),
                        ],
                      ),
                  ],
                ),
              if (!wide) const SizedBox(height: 72),
            ],
          );
        },
      ),
    );
  }
}

String _roleName(UserRole r) => switch (r) {
  UserRole.admin => 'Admin',
  UserRole.coordinator => 'Coordinator',
  UserRole.tutor => 'Tutor',
};

class _NewUser {
  final String email;
  final String fullName;
  final UserRole role;
  final int? schoolId;
  const _NewUser(this.email, this.fullName, this.role, this.schoolId);
}

class _NewUserDialog extends StatefulWidget {
  const _NewUserDialog();

  @override
  State<_NewUserDialog> createState() => _NewUserDialogState();
}

class _NewUserDialogState extends State<_NewUserDialog> {
  final _email = TextEditingController();
  final _name = TextEditingController();
  UserRole _role = UserRole.tutor;
  School? _school;

  @override
  void dispose() {
    _email.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final me = vmsOf(context).auth.currentUser;
    final superadmin = me != null && isSuperadmin(me);
    return AlertDialog(
      title: const Text('New account'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: _email, decoration: const InputDecoration(labelText: 'Email')),
              const SizedBox(height: 12),
              TextField(controller: _name, decoration: const InputDecoration(labelText: 'Full name')),
              const SizedBox(height: 12),
              BasaDropdown<UserRole>(
                label: 'Role',
                items: UserRole.values,
                value: _role,
                itemLabel: _roleName,
                onChanged: (r) => setState(() => _role = r ?? _role),
              ),
              if (superadmin) ...[
                const SizedBox(height: 12),
                SchoolPicker(value: _school, onChanged: (s) => setState(() => _school = s)),
                const SizedBox(height: 4),
                const Text('No school for an admin = a regional superadmin.'),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (_email.text.trim().isEmpty || _name.text.trim().isEmpty) return;
            Navigator.of(context).pop(_NewUser(
              _email.text.trim(),
              _name.text.trim(),
              _role,
              superadmin ? _school?.id : me?.schoolId,
            ));
          },
          child: const Text('Create'),
        ),
      ],
    );
  }
}

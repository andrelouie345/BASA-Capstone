// lib/ui/admin/first_admin_screen.dart
// First admin (docs/handoff/screens/admin.md, First admin): creates the first
// admin of a new cloud or LAN server, once per server. The temporary
// password is shown once. Admin build only.
import 'package:flutter/material.dart';

import '../common/pickers.dart';
import '../common/screen_kit.dart';
import 'admin_scope.dart';

class FirstAdminScreen extends StatefulWidget {
  const FirstAdminScreen({super.key});

  @override
  State<FirstAdminScreen> createState() => _FirstAdminScreenState();
}

class _FirstAdminScreenState extends State<FirstAdminScreen> {
  final _email = TextEditingController();
  final _name = TextEditingController();
  String _target = 'cloud';
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final email = _email.text.trim(), name = _name.text.trim();
    if (email.isEmpty || name.isEmpty) return;
    final bootstrap = AdminScope.of(context).bootstrap;
    setState(() => _busy = true);
    final password = await runAction(context, () => bootstrap.bootstrap(_target, email, name), where: 'FirstAdmin');
    if (!mounted) return;
    setState(() => _busy = false);
    if (password == null) return;
    await showTextDialog(context,
        title: 'First admin created',
        text: 'Temporary password for $email:\n\n$password\n\nIt is shown only once. They must change it at their '
            'first sign-in.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('First admin')),
      body: PageBody(
        maxWidth: 560,
        children: [
          const NoticeBanner(
            'Creates the first admin account of a new server. It works only once per server, and uses the '
            'server set in Server settings.',
            icon: Icons.admin_panel_settings_outlined,
          ),
          SectionCard(
            title: 'New admin account',
            icon: Icons.person_add_alt_1,
            children: [
              BasaDropdown<String>(
                label: 'Server',
                items: const ['cloud', 'lan'],
                value: _target,
                itemLabel: (t) => t == 'cloud' ? 'Cloud' : 'School LAN',
                onChanged: (t) => setState(() => _target = t ?? _target),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _email,
                decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.alternate_email)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Full name', prefixIcon: Icon(Icons.badge_outlined)),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _create,
                  icon: _busy
                      ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check),
                  label: const Text('Create the first admin'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

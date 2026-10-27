// lib/ui/admin/login_logs_screen.dart
// Login logs (docs/handoff/screens/admin.md): recent sign-in attempts from
// this device and the server, tagged by where each was found. Admin build only.
import 'package:flutter/material.dart';

import '../../core/models/sourced_login_log.dart';
import '../common/screen_kit.dart';
import 'admin_scope.dart';

class LoginLogsScreen extends StatefulWidget {
  const LoginLogsScreen({super.key});

  @override
  State<LoginLogsScreen> createState() => _LoginLogsScreenState();
}

class _LoginLogsScreenState extends State<LoginLogsScreen> {
  int _reload = 0;

  @override
  Widget build(BuildContext context) {
    final logs = AdminScope.of(context).loginLogs;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Login logs'),
        actions: [IconButton(tooltip: 'Refresh', onPressed: () => setState(() => _reload++), icon: const Icon(Icons.refresh))],
      ),
      body: LoadView<(List<SourcedLoginLog>, String?)>(
        where: 'LoginLogsScreen',
        reloadKey: _reload,
        load: (_) async {
          await logs.loadRecent(limit: 100);
          return (List.of(logs.items), logs.cloudError);
        },
        builder: (context, data, _) {
          final (items, cloudError) = data;
          final colors = Theme.of(context).colorScheme;
          return PageBody(
            children: [
              if (cloudError != null)
                Card(
                  color: colors.secondaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text('The server\'s log could not be read; showing this device\'s only.',
                        style: TextStyle(color: colors.onSecondaryContainer)),
                  ),
                ),
              if (items.isEmpty) const EmptyNote('No sign-in attempts recorded.'),
              for (final s in items)
                Card(
                  child: ListTile(
                    leading: Icon(s.log.success ? Icons.check_circle_outline : Icons.cancel_outlined,
                        color: s.log.success ? colors.tertiary : colors.error),
                    title: Text(s.log.emailAttempted),
                    subtitle: Text([
                      '${isoDate(s.log.timestamp.toLocal())} ${_time(s.log.timestamp.toLocal())}',
                      s.log.method.name,
                      if (!s.log.success) s.log.failureReason ?? 'failed',
                    ].join(' · ')),
                    trailing: Text(s.sourceLabel, style: Theme.of(context).textTheme.labelSmall),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

String _time(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

// lib/ui/auth/server_settings_screen.dart
// See and set the cloud and LAN server (docs/handoff/screens/auth.md, Server
// settings). The same form as the sign-in screen's dropdown. A change applies
// from the next sign-in; the session in use keeps its server.
import 'package:flutter/material.dart';

import '../basa_scope.dart';
import 'server_settings_form.dart';

class ServerSettingsScreen extends StatelessWidget {
  const ServerSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final signedIn = BasaScope.of(context).auth.isSignedIn;
    return Scaffold(
      appBar: AppBar(title: const Text('Server settings')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Saved on this device only. The anon key is the server\'s public key; '
                    'ask your coordinator for it.',
                    style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
                  ),
                  if (signedIn) ...[
                    const SizedBox(height: 8),
                    Text(
                      'A change is used from the next sign-in.',
                      style: text.bodyMedium?.copyWith(color: colors.secondary),
                    ),
                  ],
                  const SizedBox(height: 16),
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: ServerSettingsForm(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

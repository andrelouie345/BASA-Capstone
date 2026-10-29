// lib/ui/auth/server_settings_screen.dart
// See and set the cloud and LAN server (docs/handoff/screens/auth.md, Server
// settings). The same form as the sign-in screen's dropdown. A change applies
// from the next sign-in; the session in use keeps its server.
import 'package:flutter/material.dart';

import '../basa_scope.dart';
import '../common/screen_kit.dart';
import 'server_settings_form.dart';

class ServerSettingsScreen extends StatelessWidget {
  const ServerSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final signedIn = BasaScope.of(context).auth.isSignedIn;
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    return Scaffold(
      appBar: AppBar(title: const Text('Server settings')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: wide ? 1000 : 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const NoticeBanner(
                    'Saved on this device only. The anon key is the server\'s public key; '
                    'ask your coordinator for it.',
                    icon: Icons.info_outline,
                    tone: StatusTone.neutral,
                  ),
                  if (signedIn) ...[
                    const SizedBox(height: 8),
                    const NoticeBanner('A change is used from the next sign-in.', icon: Icons.schedule),
                  ],
                  const SizedBox(height: 16),
                  // Wide: the cloud and LAN blocks as two cards side by side.
                  if (wide)
                    const ServerSettingsForm(sideBySide: true)
                  else
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

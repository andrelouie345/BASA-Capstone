// lib/ui/common/version_notice.dart
// When sign-in is refused because the server and the app are on different
// BASA releases, say which side must update (docs/handoff/screens/common.md,
// Version refusal). AuthViewModel.signIn returns the refusal as text; after a
// sign-in that went through, versionWarning holds the softer notice.
//
// The kind is read from the text's first line (no typed refusal exists yet).
// If the backend's wording changes, the card still shows the full message,
// only with the general title.
import 'package:flutter/material.dart';

enum VersionRefusalKind { updateApp, updateServer, checkFailed }

/// The kind of a sign-in refusal, or null when [message] is not about versions.
VersionRefusalKind? versionRefusalKind(String message) {
  final first = message.split('\n').first;
  if (!first.startsWith('Sign-in refused:')) return null;
  if (first.contains('app is too old')) return VersionRefusalKind.updateApp;
  if (first.contains('database is older')) return VersionRefusalKind.updateServer;
  return VersionRefusalKind.checkFailed;
}

/// The refusal, with a title that says who must act. Its lines (file names
/// to apply) stay selectable so they can be copied to whoever runs the server.
class VersionRefusalCard extends StatelessWidget {
  final String message;
  const VersionRefusalCard({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final kind = versionRefusalKind(message) ?? VersionRefusalKind.checkFailed;
    final (icon, title, who) = switch (kind) {
      VersionRefusalKind.updateApp => (
        Icons.system_update,
        'Update BASA on this device',
        'This app is older than the server. Install the latest BASA, then sign in again.',
      ),
      VersionRefusalKind.updateServer => (
        Icons.dns_outlined,
        'The server needs an update',
        'The server is older than this app. Send the details below to the person who manages it.',
      ),
      VersionRefusalKind.checkFailed => (
        Icons.sync_problem,
        'Couldn\'t check the server\'s version',
        'Check the connection and try again.',
      ),
    };
    // The first line repeats the title in the backend's words: show the rest.
    final lines = message.split('\n');
    final details = lines.length > 1 ? lines.skip(1).join('\n') : lines.first;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: colors.errorContainer, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: colors.error),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title, style: text.titleMedium?.copyWith(color: colors.onErrorContainer)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(who, style: text.bodyMedium?.copyWith(color: colors.onErrorContainer)),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colors.surface.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              details,
              style: text.bodySmall?.copyWith(fontFamily: 'monospace', color: colors.onSurface, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

/// The softer notice after a sign-in that went through (the server has
/// additions this app doesn't know). Shown as a banner; [onClose] hides it.
class VersionWarningBanner extends StatelessWidget {
  final String message;
  final VoidCallback? onClose;
  const VersionWarningBanner({super.key, required this.message, this.onClose});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return MaterialBanner(
      backgroundColor: colors.secondaryContainer,
      leading: Icon(Icons.info_outline, color: colors.onSecondaryContainer),
      content: SelectableText(message, style: TextStyle(color: colors.onSecondaryContainer)),
      actions: [TextButton(onPressed: onClose, child: const Text('OK'))],
    );
  }
}

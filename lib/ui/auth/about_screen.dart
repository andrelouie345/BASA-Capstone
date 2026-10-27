// lib/ui/auth/about_screen.dart
// Which release this app is and how it compares with the server
// (docs/handoff/screens/auth.md, About / version). The release list works
// offline; the comparison needs an online sign-in, and its refusal is shown
// as is.
import 'package:flutter/material.dart';

import '../basa_scope.dart';
import '../common/error_display.dart';

class AboutScreen extends StatefulWidget {
  /// "BASA" or "BASA Tutor".
  final String appTitle;
  const AboutScreen({super.key, required this.appTitle});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  Future<({String label, String message})>? _report;

  void _check() {
    final auth = BasaScope.of(context).auth;
    setState(() => _report = auth.versionReport());
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final auth = BasaScope.of(context).auth;
    final release = auth.appRelease();
    final latest = release.isEmpty ? null : release.last;

    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(color: colors.primary, borderRadius: BorderRadius.circular(14)),
                      child: Icon(Icons.auto_stories, color: colors.onPrimary, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.appTitle, style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                          Text(
                            'Reading assessment for ARAL-Reading, CRLA and Phil-IRI',
                            style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Compared with the server', style: text.titleMedium),
                        const SizedBox(height: 8),
                        _VersionResult(report: _report),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: _check,
                            icon: const Icon(Icons.sync_alt),
                            label: Text(_report == null ? 'Check now' : 'Check again'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: ExpansionTile(
                    shape: const Border(),
                    collapsedShape: const Border(),
                    leading: const Icon(Icons.layers_outlined),
                    title: const Text('This app\'s release'),
                    subtitle: Text(
                      latest == null ? 'No database changes listed' : 'Latest: $latest',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    children: [
                      Text(
                        '${release.length} database changes this app was made for, oldest first. '
                        'The server must have the same list.',
                        style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                      ),
                      const SizedBox(height: 8),
                      for (final r in release)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: SelectableText(r, style: text.bodySmall?.copyWith(fontFamily: 'monospace')),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VersionResult extends StatelessWidget {
  final Future<({String label, String message})>? report;
  const _VersionResult({required this.report});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final r = report;
    if (r == null) {
      return Text(
        'Needs an online sign-in.',
        style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
      );
    }
    return FutureBuilder(
      future: r,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const LinearProgressIndicator();
        if (snap.hasError) return ErrorMessage(message: errorMessageFor(snap.error!, where: 'AboutScreen'));
        final v = snap.data!;
        // An empty label is a failed fetch: its message is the failure.
        if (v.label.isEmpty) return ErrorMessage(message: v.message);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Chip(
              avatar: Icon(Icons.info_outline, size: 18, color: colors.onSecondaryContainer),
              label: Text(v.label),
              backgroundColor: colors.secondaryContainer,
              labelStyle: TextStyle(color: colors.onSecondaryContainer),
            ),
            if (v.message.isNotEmpty) ...[
              const SizedBox(height: 6),
              SelectableText(v.message, style: text.bodyMedium),
            ],
          ],
        );
      },
    );
  }
}

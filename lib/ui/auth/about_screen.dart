// lib/ui/auth/about_screen.dart
// Which release this app is and how it compares with the server
// (docs/handoff/screens/auth.md, About / version). The release list works
// offline; the comparison needs an online sign-in, and its refusal is shown
// as is.
import 'package:flutter/material.dart';

import '../basa_scope.dart';
import '../common/error_display.dart';
import '../common/screen_kit.dart';
import '../theme/basa_theme.dart';

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
                // The header: same gradient as the home screen's welcome card.
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(BasaRadius.large),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [colors.primaryContainer, Color.lerp(colors.primaryContainer, colors.secondaryContainer, 0.55)!],
                    ),
                  ),
                  child: Row(
                    children: [
                      IconBadge(Icons.auto_stories, size: 56, background: colors.primary, foreground: colors.onPrimary),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(widget.appTitle,
                                style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: colors.onPrimaryContainer)),
                            const SizedBox(height: 2),
                            Text(
                              'Reading assessment for ARAL-Reading, CRLA and Phil-IRI',
                              style: text.bodyMedium?.copyWith(color: colors.onPrimaryContainer.withValues(alpha: 0.8)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                StatGrid(tileWidth: 200, tiles: [
                  StatTile(label: 'Database changes', value: '${release.length}', icon: Icons.layers_outlined),
                  StatTile(label: 'Latest', value: latest ?? '—', icon: Icons.new_releases_outlined),
                ]),
                const SizedBox(height: 12),
                SectionCard(
                  title: 'Compared with the server',
                  icon: Icons.compare_arrows,
                  trailing: OutlinedButton.icon(
                    onPressed: _check,
                    icon: const Icon(Icons.sync_alt),
                    label: Text(_report == null ? 'Check now' : 'Check again'),
                  ),
                  children: [_VersionResult(report: _report)],
                ),
                const SizedBox(height: 12),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: ExpansionTile(
                    shape: const Border(),
                    collapsedShape: const Border(),
                    leading: const IconBadge(Icons.layers_outlined, size: 34),
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
                      for (final (i, r) in release.indexed)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: i.isEven ? colors.surfaceContainerLowest : colors.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(6),
                          ),
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
      return Row(children: [
        Icon(Icons.cloud_off, size: 18, color: colors.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(child: Text('Needs an online sign-in.', style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant))),
      ]);
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
            StatusChip(v.label, tone: StatusTone.warn, icon: Icons.info_outline),
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

// lib/ui/home/home_screen.dart
// The signed-in home: one page per section (home_sections.dart), switched by
// a navigation rail on wide screens and a bottom bar (or a drawer, when there
// are more than five sections) on phones. Each page lists its screens as
// cards; a screen opens on top of the home with the normal back button.
// The status chip and the pending-work banner read the device again whenever
// the user comes back from a screen.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../auth/account_menu.dart';
import '../basa_scope.dart';
import '../common/connection_status.dart';
import '../common/signed_in_user.dart';
import 'home_sections.dart';

/// At least this wide: a navigation rail instead of the bottom bar.
const _railWidth = 600.0;

/// At least this wide: the rail shows its labels beside the icons.
const _extendedRailWidth = 1000.0;

class HomeScreen extends StatefulWidget {
  /// "BASA" or "BASA Tutor".
  final String title;
  final List<HomeSection> sections;

  /// Called after signing out, so the app shell shows the sign-in screen.
  final VoidCallback onSignedOut;

  const HomeScreen({super.key, required this.title, required this.sections, required this.onSignedOut});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  /// Bumped after a screen closes: new keys make the chip and banner reload.
  int _epoch = 0;

  HomeSection get _section => widget.sections[_index];

  void _select(int i) => setState(() => _index = i);

  void _selectId(String id) {
    final i = widget.sections.indexWhere((s) => s.id == id);
    if (i >= 0) _select(i);
  }

  Future<void> _open(HomeEntry entry) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: entry.builder ?? (_) => NotBuiltScreen(entry: entry)),
    );
    if (mounted) setState(() => _epoch++);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= _railWidth;
    final useDrawer = !wide && widget.sections.length > 5;
    final title = _index == 0 ? widget.title : _section.label;

    final page = _SectionPage(
      key: ValueKey('${_section.id}-$_epoch'),
      section: _section,
      onOpen: _open,
    );

    final scaffold = Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          ConnectionStatusChip(
            key: ValueKey('chip-$_epoch'),
            onTap: () => _selectId(HomeSectionIds.sync),
          ),
          AccountMenu(appTitle: widget.title, onSignedOut: widget.onSignedOut),
          const SizedBox(width: 4),
        ],
      ),
      drawer: useDrawer ? _drawer(context) : null,
      body: wide
          ? Row(
              children: [
                _rail(context, extended: width >= _extendedRailWidth),
                const VerticalDivider(width: 1),
                Expanded(child: page),
              ],
            )
          : page,
      bottomNavigationBar: wide || useDrawer
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: _select,
              destinations: [
                for (final s in widget.sections)
                  NavigationDestination(icon: Icon(s.icon), selectedIcon: Icon(s.selectedIcon), label: s.label),
              ],
            ),
    );

    // Back on another section goes to Home first, then leaves the app.
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _select(0);
      },
      child: scaffold,
    );
  }

  Widget _rail(BuildContext context, {required bool extended}) => NavigationRail(
    selectedIndex: _index,
    onDestinationSelected: _select,
    extended: extended,
    labelType: extended ? NavigationRailLabelType.none : NavigationRailLabelType.all,
    destinations: [
      for (final s in widget.sections)
        NavigationRailDestination(icon: Icon(s.icon), selectedIcon: Icon(s.selectedIcon), label: Text(s.label)),
    ],
  );

  Widget _drawer(BuildContext context) => NavigationDrawer(
    selectedIndex: _index,
    onDestinationSelected: (i) {
      Navigator.of(context).pop();
      _select(i);
    },
    children: [
      const Padding(padding: EdgeInsets.fromLTRB(12, 16, 12, 8), child: SignedInUserTile(showEmail: false)),
      const Divider(indent: 28, endIndent: 28),
      const SizedBox(height: 8),
      for (final s in widget.sections)
        NavigationDrawerDestination(icon: Icon(s.icon), selectedIcon: Icon(s.selectedIcon), label: Text(s.label)),
    ],
  );
}

/// One section: its groups of screen cards; the Home section also greets.
class _SectionPage extends StatelessWidget {
  final HomeSection section;
  final ValueChanged<HomeEntry> onOpen;
  const _SectionPage({super.key, required this.section, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final isHome = section.id == HomeSectionIds.home;
    return Column(
      children: [
        const PendingWorkBanner(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (isHome) ...[const _WelcomeCard(), const SizedBox(height: 24)],
                      for (final g in section.groups) ...[
                        _GroupTitle(g.title),
                        const SizedBox(height: 10),
                        _EntryGrid(entries: g.entries, onOpen: onOpen),
                        const SizedBox(height: 24),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GroupTitle extends StatelessWidget {
  final String text;
  const _GroupTitle(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text.toUpperCase(),
      style: theme.textTheme.labelMedium?.copyWith(
        color: theme.colorScheme.primary,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
      ),
    );
  }
}

/// Cards in as many columns as fit (about 320 px each).
class _EntryGrid extends StatelessWidget {
  final List<HomeEntry> entries;
  final ValueChanged<HomeEntry> onOpen;
  const _EntryGrid({required this.entries, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 12.0;
        final columns = (constraints.maxWidth / 320).floor().clamp(1, 4);
        final cardWidth = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final e in entries)
              SizedBox(width: cardWidth, child: _EntryCard(entry: e, onTap: () => onOpen(e))),
          ],
        );
      },
    );
  }
}

class _EntryCard extends StatelessWidget {
  final HomeEntry entry;
  final VoidCallback onTap;
  const _EntryCard({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final built = entry.builder != null;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: built ? colors.primaryContainer : colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(entry.icon, color: built ? colors.onPrimaryContainer : colors.onSurfaceVariant),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.title, style: theme.textTheme.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(
                      entry.description,
                      style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              built
                  ? Icon(Icons.chevron_right, color: colors.onSurfaceVariant)
                  : Text('Soon', style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Good morning" and who is signed in, with a note when working offline.
class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final auth = BasaScope.of(context).auth;
    return Card(
      color: colors.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                greetingFor(DateTime.now()),
                style: theme.textTheme.headlineSmall?.copyWith(color: colors.onPrimaryContainer),
              ),
            ),
            const SignedInUserTile(),
            if (auth.isOffline)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    Icon(Icons.cloud_off, size: 18, color: colors.onPrimaryContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Signed in offline: your work is saved on this device until you send it.',
                        style: theme.textTheme.bodySmall?.copyWith(color: colors.onPrimaryContainer),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// "Good morning" before noon, "Good afternoon" before six, else "Good evening".
String greetingFor(DateTime now) => now.hour < 12
    ? 'Good morning'
    : now.hour < 18
    ? 'Good afternoon'
    : 'Good evening';

/// Opened by an entry whose screen isn't built yet. Debug builds also say
/// where its checklist row and screen block are.
class NotBuiltScreen extends StatelessWidget {
  final HomeEntry entry;
  const NotBuiltScreen({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(entry.title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(entry.icon, size: 56, color: colors.onSurfaceVariant),
              const SizedBox(height: 16),
              Text('Coming soon', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                'This screen is not in the app yet.',
                style: theme.textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              if (kDebugMode) ...[
                const SizedBox(height: 16),
                SelectableText(
                  'Checklist row ${entry.checklistRow} · docs/handoff/screens/${entry.doc}',
                  style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// lib/ui/example/example_screen.dart
// EXAMPLE, REPLACE ME. Debug build only: opened from the debug console's
// header button, never reachable in a release build (the console is compiled
// out there, see basaHasConsole in lib/app_shell.dart).
//
// It shows the pattern every BASA screen follows, on the Dashboard home
// (docs/handoff/screens/dashboard.md):
//   1. get the ViewModels with BasaScope.of(context);
//   2. call a method and await it; the screen keeps its own loading / error /
//      result state (ViewModels don't notify);
//   3. show a ViewModelException's message as is; anything else gets
//      unexpectedErrorMessage, and the detail goes to the log;
//   4. colours come from the theme only, so light and dark mode both work.
// Layout and styling here are placeholders: build the real screen your way.
import 'package:flutter/material.dart';

import '../../core/models/messages.dart';
import '../../viewmodels/dashboard_viewmodel.dart';
import '../../viewmodels/viewmodel_exception.dart';
import '../basa_scope.dart';

class ExampleScreen extends StatefulWidget {
  const ExampleScreen({super.key});

  @override
  State<ExampleScreen> createState() => _ExampleScreenState();
}

class _ExampleScreenState extends State<ExampleScreen> {
  bool _loading = true;
  String? _error;
  List<String> _years = const [];
  String? _year;
  DashboardSummary? _summary;

  @override
  void initState() {
    super.initState();
    // Load after the first frame: setState can't run while the tree builds.
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadYears());
  }

  // Read the ViewModel before any await: context must not be used across one.
  DashboardViewModel get _dashboard => BasaScope.of(context).dashboard;

  Future<void> _loadYears() async {
    final dashboard = _dashboard;
    await _run(() async {
      final years = await dashboard.schoolYears();
      _years = years;
      _year = years.isEmpty ? null : years.first;
      _summary = _year == null ? null : await dashboard.summary(_year!);
    });
  }

  Future<void> _pickYear(String year) async {
    final dashboard = _dashboard;
    _year = year;
    await _run(() async => _summary = await dashboard.summary(year));
  }

  /// One place for the loading flag and the error rule.
  Future<void> _run(Future<void> Function() call) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await call();
    } on ViewModelException catch (e) {
      _error = e.message; // written for the user: show it as is
    } catch (e) {
      debugPrint('ExampleScreen: $e'); // the detail goes to the log only
      _error = unexpectedErrorMessage;
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Example screen (replace me)')),
      // No years yet: the whole body is the spinner or the message. Once
      // there are years, the picker stays on screen whatever happens below it,
      // so a year that fails never traps the user.
      body: _years.isEmpty
          ? _loading
              ? const Center(child: CircularProgressIndicator())
              : _Message(
                  text: _error ?? 'No school years on this device yet. Download the latest data first.',
                  color: _error != null ? colors.error : colors.onSurface,
                  onRetry: _loadYears)
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                DropdownButton<String>(
                  value: _year,
                  items: [for (final y in _years) DropdownMenuItem(value: y, child: Text(y))],
                  onChanged: _loading ? null : (y) => y == null ? null : _pickYear(y),
                ),
                const SizedBox(height: 8),
                if (_loading)
                  const Center(child: CircularProgressIndicator())
                else if (_error != null)
                  // "Try again" repeats the call that failed: the picked year's summary.
                  _Message(text: _error!, color: colors.error, onRetry: () => _pickYear(_year!))
                else
                  ..._summaryTiles(_summary),
              ],
            ),
    );
  }

  // DashboardSummary is sealed: one case per role, and the compiler checks
  // that every case is handled.
  List<Widget> _summaryTiles(DashboardSummary? s) => switch (s) {
        null => const [],
        TutorDashboard t => [
            ListTile(title: const Text('Tutor'), subtitle: Text(t.tutorName ?? t.tutorId)),
            for (final (section, learners) in t.sections)
              ListTile(title: Text('$section'), trailing: Text('$learners learners')),
            ListTile(title: const Text('ARAL learners'), trailing: Text('${t.aral.active} active')),
            ListTile(title: const Text('Sessions held'), trailing: Text('${t.reminders.sessionsHeld}')),
          ],
        SchoolDashboard d => [
            ListTile(title: const Text('School'), subtitle: Text(d.school.school.schoolName)),
            ListTile(title: const Text('ARAL learners'), trailing: Text('${d.school.aral.active} active')),
          ],
        RegionDashboard r => [
            ListTile(title: const Text('Schools'), trailing: Text('${r.schools.length}')),
            ListTile(title: const Text('ARAL learners'), trailing: Text('${r.aral.active} active')),
            ListTile(title: const Text('SRP classes'), trailing: Text('${r.srpClasses}')),
          ],
      };
}

class _Message extends StatelessWidget {
  final String text;
  final Color color;
  final VoidCallback onRetry;
  const _Message({required this.text, required this.color, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(text, style: TextStyle(color: color), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
          ]),
        ),
      );
}

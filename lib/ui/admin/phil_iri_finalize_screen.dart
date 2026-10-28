// lib/ui/admin/phil_iri_finalize_screen.dart
// Finalize (docs/handoff/screens/phil-iri.md): close a section's Phil-IRI
// round: every completed session is finalized; sessions still in progress
// are counted and left as they are. Admin build only.
import 'package:flutter/material.dart';

import '../../core/models/phil_iri_assessment.dart';
import '../../core/models/section.dart';
import '../common/pickers.dart';
import '../common/screen_kit.dart';
import '../phil_iri/gst_screen.dart';

class PhilIriFinalizeScreen extends StatefulWidget {
  const PhilIriFinalizeScreen({super.key});

  @override
  State<PhilIriFinalizeScreen> createState() => _PhilIriFinalizeScreenState();
}

class _PhilIriFinalizeScreenState extends State<PhilIriFinalizeScreen> {
  Section? _section;
  PhilIriRound _round = PhilIriRound.values.first;
  String? _result;
  (int, int, int)? _counts;
  bool _busy = false;

  Future<void> _finalize() async {
    final section = _section;
    if (section == null) return;
    if (!await confirm(context,
        title: 'Finalize ${_round.label} for $section?',
        body: 'Completed sessions can no longer be changed after this.',
        action: 'Finalize')) {
      return;
    }
    if (!mounted) return;
    final vm = vmsOf(context).philIri;
    setState(() => _busy = true);
    final r = await runAction(context,
        () => vm.finalizeRound(sectionId: section.id!, schoolYear: section.schoolYear, round: _round),
        where: 'PhilIriFinalize');
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r != null) {
        _counts = (r.finalized.length, r.alreadyFinalized.length, r.stillInProgress.length);
        _result = 'Finalized: ${r.finalized.length}\nAlready finalized: ${r.alreadyFinalized.length}\n'
            'Still in progress (left open): ${r.stillInProgress.length}';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final wide = isWideScreen(context);
    final ready = !_busy && _section != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Finalize Phil-IRI'),
        actions: [
          if (wide)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: FilledButton.icon(
                onPressed: ready ? _finalize : null,
                icon: const Icon(Icons.task_alt),
                label: const Text('Finalize the round'),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
              ),
            ),
        ],
      ),
      floatingActionButton: wide || _section == null
          ? null
          : FloatingActionButton.extended(
              onPressed: ready ? _finalize : null,
              icon: _busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.task_alt),
              label: const Text('Finalize the round'),
            ),
      body: PageBody(
        maxWidth: 720,
        children: [
          FilterBar(children: [
            SectionPicker(value: _section, onChanged: (s) => setState(() => _section = s), where: philIriGrade),
            PhilIriRoundPicker(value: _round, onChanged: (r) => setState(() => _round = r ?? _round)),
          ]),
          const NoticeBanner(
            'Finalizing locks every completed session of the round. Sessions still in progress stay open.',
            icon: Icons.lock_outline,
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_section == null && _result == null)
            const EmptyNote('Pick a section and a round to finalize.', icon: Icons.task_alt),
          if (_result != null)
            SectionCard(
              title: 'Done',
              icon: Icons.task_alt,
              children: [
                if (_counts != null) ...[
                  StatGrid(tileWidth: 180, tiles: [
                    StatTile(label: 'Finalized', value: '${_counts!.$1}', icon: Icons.lock_outline),
                    StatTile(label: 'Already finalized', value: '${_counts!.$2}', icon: Icons.history),
                    StatTile(label: 'Still in progress (left open)', value: '${_counts!.$3}', icon: Icons.pending_outlined),
                  ]),
                  const SizedBox(height: 12),
                ],
                Text(_result!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
        ],
      ),
    );
  }
}

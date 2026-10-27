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
        _result = 'Finalized: ${r.finalized.length}\nAlready finalized: ${r.alreadyFinalized.length}\n'
            'Still in progress (left open): ${r.stillInProgress.length}';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Finalize Phil-IRI')),
      body: PageBody(
        maxWidth: 640,
        children: [
          SectionPicker(value: _section, onChanged: (s) => setState(() => _section = s), where: philIriGrade),
          PhilIriRoundPicker(value: _round, onChanged: (r) => setState(() => _round = r ?? _round)),
          FilledButton.icon(
            onPressed: _busy || _section == null ? null : _finalize,
            icon: const Icon(Icons.task_alt),
            label: const Text('Finalize the round'),
          ),
          if (_result != null) SectionCard(title: 'Done', children: [Text(_result!)]),
        ],
      ),
    );
  }
}

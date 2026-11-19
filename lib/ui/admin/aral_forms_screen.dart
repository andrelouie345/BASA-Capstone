// lib/ui/admin/aral_forms_screen.dart
// ARAL Forms 1, 2 and 4 (Reading), Division Memorandum 180 s. 2026
// (docs/handoff/screens/aral.md#aral-forms-1-2-and-4-reading): each saved as
// an Excel file from this device's copy, in BASA's own layout. What BASA
// doesn't hold is left blank for hand entry; each form's notes show here
// after saving. Forms 3, 5 and 6 are not in BASA. Admin build only.
import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/models/aral_class.dart';
import '../../viewmodels/aral_forms_viewmodel.dart';
import '../common/screen_kit.dart';
import '../common/school_year_scope.dart';
import 'admin_scope.dart';

class AralFormsScreen extends StatelessWidget {
  const AralFormsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ARAL Forms 1, 2 and 4')),
      body: PageBody(
        children: [
          SchoolYearScope(builder: (context, schoolId, year) => _Body(key: ValueKey('$schoolId-$year'), schoolId: schoolId, year: year)),
        ],
      ),
    );
  }
}

class _Body extends StatefulWidget {
  final int schoolId;
  final String year;
  const _Body({super.key, required this.schoolId, required this.year});

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  AralClass? _class; // null = every class
  String _asOf = isoDate(DateTime.now());
  final Map<int, List<String>> _notes = {}; // form number -> notes of the last save

  String _file(String form) => 'ARAL_$form${_class != null && form == 'Form1' ? '_${_class!.className}' : ''}_${widget.year}.xlsx';

  /// Saves one form: [make] returns the file's bytes and its notes.
  Future<void> _save(int form, String fileName, Future<(List<int>, List<String>)> Function() make) async {
    final r = await runAction(context, () async {
      final (bytes, notes) = await make();
      final out = await exportPath(fileName);
      await File(out).writeAsBytes(bytes);
      return (out, notes);
    }, where: 'AralForms');
    if (r == null || !mounted) return;
    setState(() => _notes[form] = r.$2);
    await showTextDialog(context, title: 'Saved', text: [r.$1, ...r.$2].join('\n\n'));
  }

  Future<void> _pickClass() async {
    final vms = vmsOf(context);
    final classes = await runAction(context, () => vms.aralClass.classes(schoolId: widget.schoolId, schoolYear: widget.year),
        where: 'AralForms');
    if (classes == null || !mounted) return;
    if (classes.isEmpty) return showNote(context, 'This school has no ARAL classes for ${widget.year} yet.');
    const all = -1;
    final id = await pickOne<int>(context,
        title: 'Form 1 for',
        options: [all, for (final c in classes) c.id!],
        label: (id) => id == all ? 'Every class (one sheet each)' : classes.firstWhere((c) => c.id == id).className);
    if (id == null || !mounted) return;
    setState(() => _class = id == all ? null : classes.firstWhere((c) => c.id == id));
  }

  @override
  Widget build(BuildContext context) {
    final forms = AdminScope.of(context).aralForms;
    final schoolId = widget.schoolId, year = widget.year;
    Widget notes(int form) {
      final n = _notes[form];
      if (n == null || n.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: NoticeBanner(n.join('\n'), icon: Icons.info_outline, tone: StatusTone.neutral),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const NoticeBanner(
          "Saved from this device's copy: download the latest data first. Forms 3, 5 and 6 are kept in the "
          "separate tutor-management system; BASA's sessions give each tutor's ARAL hours for them.",
          icon: Icons.description_outlined,
          tone: StatusTone.neutral,
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Form 1: class list',
          icon: Icons.groups_outlined,
          children: [
            const Text('One sheet per class: the class, its tutor and schedule, and each learner with their MoSY result.'),
            const SizedBox(height: 12),
            Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
              OutlinedButton.icon(
                onPressed: _pickClass,
                icon: const Icon(Icons.class_outlined),
                label: Text(_class == null ? 'Every class' : _class!.className),
              ),
              FilledButton.icon(
                onPressed: () => _save(1, _file('Form1'), () async {
                  final bytes = await forms.form1Xlsx(schoolId: schoolId, schoolYear: year, classId: _class?.id);
                  return (bytes, ['Left blank for hand entry: ${AralFormsViewModel.form1Blanks.join(', ')}.']);
                }),
                icon: const Icon(Icons.save_alt),
                label: const Text('Save .xlsx'),
              ),
            ]),
            notes(1),
          ],
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Form 2: classes',
          icon: Icons.table_rows_outlined,
          children: [
            const Text("One row per class: learners, the class's MoSY result, tutor and type, the tutor's advisory "
                'class, schedule and venue; the number of classes, learners and tutors.'),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: () => _save(2, _file('Form2'), () async {
                  final bytes = await forms.form2Xlsx(schoolId: schoolId, schoolYear: year);
                  final f = await forms.form2(schoolId: schoolId, schoolYear: year);
                  return (bytes, ['Left blank for hand entry: ${f.blanks.join(', ')}.', ...f.notes]);
                }),
                icon: const Icon(Icons.save_alt),
                label: const Text('Save .xlsx'),
              ),
            ),
            notes(2),
          ],
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Form 4: progress report',
          icon: Icons.trending_up,
          children: [
            const Text('Per grade, as of a date: learners identified at BoSY, served, reached grade level, improved, '
                'no improvement and in ARAL at MoSY; then classes, tutors, sessions and hours.'),
            const SizedBox(height: 12),
            Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
              OutlinedButton.icon(
                onPressed: () async {
                  final d = await pickDate(context, initial: _asOf);
                  if (d != null && mounted) setState(() => _asOf = d);
                },
                icon: const Icon(Icons.event_outlined),
                label: Text('As of $_asOf'),
              ),
              FilledButton.icon(
                onPressed: () => _save(4, 'ARAL_Form4_${year}_$_asOf.xlsx', () async {
                  final bytes = await forms.form4Xlsx(schoolId: schoolId, schoolYear: year, asOf: _asOf);
                  final f = await forms.form4(schoolId: schoolId, schoolYear: year, asOf: _asOf);
                  return (bytes, f.notes);
                }),
                icon: const Icon(Icons.save_alt),
                label: const Text('Save .xlsx'),
              ),
            ]),
            notes(4),
          ],
        ),
      ],
    );
  }
}

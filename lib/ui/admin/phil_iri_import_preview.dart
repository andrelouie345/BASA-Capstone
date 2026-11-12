// lib/ui/admin/phil_iri_import_preview.dart
// The parts of the Phil-IRI import preview (docs/handoff/screens/phil-iri-import.md):
// the search and "Show" filter, one card per section sheet with its rows,
// the cells that couldn't be read, and the headers step. Admin build only.
import 'package:flutter/material.dart';

import '../../core/models/phil_iri_import.dart';
import '../../core/models/student.dart';
import '../../viewmodels/phil_iri_import_viewmodel.dart';
import '../common/pickers.dart';
import '../common/screen_kit.dart';

/// What the "Show" filter keeps.
enum PreviewShow {
  all('All'),
  needsPick('Needs a pick'),
  flagged('Flagged'),
  skipped('Skipped'),
  unreadable('Unreadable cells');

  final String label;
  const PreviewShow(this.label);
}

String studentLabel(Student s) => '${s.lastName}, ${s.firstName}${s.middleName == null || s.middleName!.trim().isEmpty ? '' : ' ${s.middleName!.trim()[0]}.'}';

/// The learner as the file names them (name or LRN).
String fileLearner(PhilIriImportRow r) => r.learner.name ?? (r.learner.lrn == null ? '?' : 'LRN ${r.learner.lrn}');

/// True when [r] passes the search [query] and the [show] filter. The
/// candidates of a pick are not searched: they are the whole section (name
/// matches first), so every unpicked row would match every learner.
bool rowShown(PhilIriImportRow r, PhilIriImportSectionPreview s, String query, PreviewShow show) {
  final keep = switch (show) {
    PreviewShow.all => true,
    PreviewShow.needsPick => r.candidates.isNotEmpty,
    PreviewShow.flagged => r.outcome == PhilIriImportOutcome.importFlagged,
    PreviewShow.skipped => r.outcome == PhilIriImportOutcome.skipped,
    PreviewShow.unreadable => false,
  };
  if (!keep) return false;
  return matchesSearch(query, [
    r.learner.name,
    r.learner.lrn,
    if (r.student != null) studentLabel(r.student!),
    'sheet ${s.ref.sheet}',
    s.ref.sectionName,
    s.section?.sectionName,
    r.gst != null ? 'GST' : r.round?.label,
    r.reading == null ? null : (r.passage?.title ?? 'Untitled'),
    ...r.notes,
  ]);
}

/// One section sheet: its status, counts, tick box and (open) its rows.
class SectionPreviewCard extends StatefulWidget {
  final PhilIriImportSectionPreview section;
  final List<PhilIriImportRow> rows; // already filtered
  final bool filtering;
  final bool? ticked; // null = no tick box (scoresheet)
  final ValueChanged<bool>? onTick;
  final Map<String, int> picks;
  final Map<String, List<Student>> candidates;
  final void Function(String learnerRef, int? studentId) onPick;

  const SectionPreviewCard({
    super.key,
    required this.section,
    required this.rows,
    required this.filtering,
    required this.ticked,
    required this.onTick,
    required this.picks,
    required this.candidates,
    required this.onPick,
  });

  @override
  State<SectionPreviewCard> createState() => _SectionPreviewCardState();
}

class _SectionPreviewCardState extends State<SectionPreviewCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.section;
    final open = _open || widget.filtering;
    final (tone, icon) = switch (s.status) {
      PhilIriImportSectionPreview.importable => (StatusTone.good, Icons.check_circle_outline),
      PhilIriImportSectionPreview.alreadyImported => (StatusTone.warn, Icons.lock_outline),
      PhilIriImportSectionPreview.notInBasa => (StatusTone.bad, Icons.help_outline),
      _ => (StatusTone.neutral, Icons.remove_circle_outline),
    };
    final name = s.section == null
        ? '${s.ref.sectionName ?? 'no section name'} (not in BASA)'
        : 'Grade ${s.section!.gradeLevel} ${s.section!.sectionName}';
    final shownPick = <String>{};
    return SectionCard(
      title: 'Sheet ${s.ref.sheet} · $name',
      icon: Icons.table_chart_outlined,
      trailing: widget.ticked == null
          ? null
          : Checkbox(
              key: Key('philIriImport.tick.${s.ref.sheet}'),
              value: widget.ticked,
              onChanged: s.status == PhilIriImportSectionPreview.importable ? (v) => widget.onTick?.call(v ?? false) : null,
            ),
      children: [
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          StatusChip(s.status, tone: tone, icon: icon),
          StatusChip('To import ${s.count(PhilIriImportOutcome.import)}', tone: StatusTone.good),
          StatusChip('Flagged ${s.count(PhilIriImportOutcome.importFlagged)}', tone: StatusTone.warn),
          StatusChip('Skipped ${s.count(PhilIriImportOutcome.skipped)}'),
        ]),
        for (final n in s.notes) ...[const SizedBox(height: 8), NoticeBanner(n, tone: StatusTone.neutral)],
        if (s.rows.isNotEmpty && !widget.filtering)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _open = !_open),
              icon: Icon(open ? Icons.expand_less : Icons.expand_more),
              label: Text(open ? 'Hide rows' : 'Show ${s.rows.length} row(s)'),
            ),
          ),
        if (open)
          for (final r in widget.rows) ...[
            const Divider(),
            _PreviewRow(
              row: r,
              pickHere: (r.candidates.isNotEmpty || widget.picks.containsKey(r.learnerRef)) && shownPick.add(r.learnerRef),
              picked: widget.picks[r.learnerRef],
              candidates: widget.candidates[r.learnerRef] ?? r.candidates,
              onPick: (id) => widget.onPick(r.learnerRef, id),
            ),
          ],
      ],
    );
  }
}

/// One entry: a reading or a GST, what BASA will make of it, and its notes;
/// the learner pick on the learner's first row.
class _PreviewRow extends StatelessWidget {
  final PhilIriImportRow row;
  final bool pickHere;
  final int? picked;
  final List<Student> candidates;
  final ValueChanged<int?> onPick;

  const _PreviewRow({required this.row, required this.pickHere, required this.picked, required this.candidates, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final r = row;
    final colors = Theme.of(context).colorScheme;
    final (icon, tone, label) = switch (r.outcome) {
      PhilIriImportOutcome.import => (Icons.check_rounded, StatusTone.good, 'To import'),
      PhilIriImportOutcome.importFlagged => (Icons.flag_outlined, StatusTone.warn, 'Flagged'),
      PhilIriImportOutcome.skipped => (Icons.block, StatusTone.neutral, 'Skipped'),
    };
    final accent = switch (tone) {
      StatusTone.good => colors.tertiary,
      StatusTone.warn => colors.secondary,
      _ => colors.onSurfaceVariant,
    };
    final what = r.gst != null
        ? 'GST ${r.gst!.score}${r.gst!.max == null ? '' : '/${r.gst!.max}'}'
        : [
            r.round?.label ?? '',
            if (r.reading != null) r.passage?.title ?? 'Untitled',
          ].where((x) => x.isNotEmpty).join(' · ');
    final basa = [
      if (r.basaProfile != null) 'BASA: ${r.basaProfile}',
      if (r.basaAdjustedLevel != null) 'Grade ${r.basaAdjustedLevel}',
    ].join(' · ');
    final matched = r.student == null ? '' : ' → ${studentLabel(r.student!)}';
    final value = picked == null ? null : candidates.where((c) => c.id == picked).firstOrNull;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        IconBadge(icon, size: 32, background: accent.withValues(alpha: 0.14), foreground: accent),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${fileLearner(r)}$matched', style: Theme.of(context).textTheme.titleSmall),
            Text(
              [r.ref.toString(), what, if (basa.isNotEmpty) basa].join(' · '),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            Wrap(spacing: 8, runSpacing: 4, children: [
              StatusChip(label, tone: tone),
              for (final n in r.notes) Text(n, style: Theme.of(context).textTheme.bodySmall),
            ]),
            if (pickHere && candidates.isNotEmpty) ...[
              const SizedBox(height: 8),
              BasaDropdown<Student>(
                key: Key('philIriImport.pick.${r.learnerRef}'),
                label: 'Which BASA learner is this?',
                items: candidates,
                value: value,
                allowNone: true,
                hint: 'Skip (not imported)',
                itemLabel: (s) => '${studentLabel(s)} · LRN ${s.lrn}',
                onChanged: (s) => onPick(s?.id),
              ),
            ],
          ]),
        ),
      ]),
    );
  }
}

/// The cells the reader could not read, with where they are.
class UnreadableCard extends StatelessWidget {
  final List<PhilIriImportProblem> problems;
  const UnreadableCard({super.key, required this.problems});

  @override
  Widget build(BuildContext context) => SectionCard(
    title: 'Cells that could not be read (${problems.length})',
    icon: Icons.report_problem_outlined,
    children: [
      for (final p in problems)
        Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: SelectableText('${p.ref}: ${p.message}')),
    ],
  );
}

/// Header issues: nothing was read. For each one, pick the file's header for
/// the field (check its values first), then save and preview again.
class HeadersStep extends StatefulWidget {
  final List<PhilIriHeaderIssue> issues;
  final Map<String, String> labels; // field -> label BASA looks for
  final Future<void> Function(String field, String header) onSamples;
  final Future<void> Function(Map<String, String> picks) onSave;
  const HeadersStep({super.key, required this.issues, required this.labels, required this.onSamples, required this.onSave});

  @override
  State<HeadersStep> createState() => _HeadersStepState();
}

class _HeadersStepState extends State<HeadersStep> {
  final _picks = <String, String>{};

  @override
  Widget build(BuildContext context) {
    final fields = <String>{};
    return SectionCard(
      title: 'Column headers to check',
      icon: Icons.view_column_outlined,
      children: [
        const NoticeBanner(
          'Nothing was read yet: a column header in the file differs from the one BASA looks for. '
          'Pick the file\'s header for each field, check its values, then save and preview again.',
        ),
        for (final i in widget.issues)
          if (fields.add(i.field)) ...[
            const Divider(),
            Text('BASA looks for “${widget.labels[i.field] ?? i.field}”', style: Theme.of(context).textTheme.titleSmall),
            Text('Missing in: ${i.block}', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: BasaDropdown<String>(
                  label: 'The file\'s header',
                  items: i.found,
                  value: _picks[i.field],
                  itemLabel: (h) => h,
                  onChanged: (h) => setState(() => h == null ? _picks.remove(i.field) : _picks[i.field] = h),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _picks[i.field] == null ? null : () => widget.onSamples(i.field, _picks[i.field]!),
                child: const Text('Check values'),
              ),
            ]),
          ],
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _picks.isEmpty ? null : () => widget.onSave(Map.of(_picks)),
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save and preview again'),
          ),
        ),
      ],
    );
  }
}

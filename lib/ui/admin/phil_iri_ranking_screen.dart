// lib/ui/admin/phil_iri_ranking_screen.dart
// Phil-IRI ranking list (docs/handoff/screens/value-sources.md#ranking-list):
// the learners with the lowest values in one round for one measure, in one
// section, one grade or the whole school, as of a date. Ranked learners first
// (equal values share a rank), then the learners with no value and why; the
// list says which values it uses and saves as CSV. Runs on the Rank button
// (a whole school reads every learner's year). Admin build only.
import 'package:flutter/material.dart';

import '../../core/models/phil_iri_assessment.dart';
import '../../core/models/report_setting.dart' show philIriValuesLabel;
import '../../core/models/section.dart';
import '../../viewmodels/phil_iri_ranking_viewmodel.dart';
import '../common/pickers.dart';
import '../common/screen_kit.dart';
import '../common/school_year_scope.dart';
import '../phil_iri/session_screen.dart' show philIriLevelTone;
import 'admin_scope.dart';

class PhilIriRankingScreen extends StatelessWidget {
  const PhilIriRankingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Phil-IRI ranking')),
      body: PageBody(
        maxWidth: 1200,
        children: [
          const Text('The learners with the lowest values in one round, for one measure.'),
          SchoolYearScope(
            builder: (context, schoolId, year) =>
                _RankingBody(key: ValueKey('$schoolId-$year'), schoolId: schoolId, year: year),
          ),
        ],
      ),
    );
  }
}

enum _Scope { school, grade, section }

class _RankingBody extends StatefulWidget {
  final int schoolId;
  final String year;
  const _RankingBody({super.key, required this.schoolId, required this.year});

  @override
  State<_RankingBody> createState() => _RankingBodyState();
}

class _RankingBodyState extends State<_RankingBody> {
  PhilIriRound? _round = PhilIriRound.bosy;
  PhilIriRankMeasure? _measure = PhilIriRankMeasure.comprehension;
  _Scope _scope = _Scope.school;
  int? _grade;
  Section? _section;
  final _n = TextEditingController(text: '10');
  String _asOf = isoDate(DateTime.now());
  bool _busy = false;
  PhilIriRanking? _ranking;

  @override
  void dispose() {
    _n.dispose();
    super.dispose();
  }

  String? get _missing {
    if (_round == null) return 'Pick a round.';
    if (_measure == null) return 'Pick a measure.';
    if (_scope == _Scope.grade && _grade == null) return 'Pick a grade.';
    if (_scope == _Scope.section && _section == null) return 'Pick a section.';
    return null;
  }

  Future<void> _rank() async {
    final missing = _missing;
    if (missing != null) return showNote(context, missing);
    final n = int.tryParse(_n.text.trim());
    if (n == null) return showNote(context, 'How many is a whole number (at least 1).');
    final vm = AdminScope.of(context).philIriRanking;
    setState(() => _busy = true);
    final r = await runAction(
      context,
      () => vm.rank(
        schoolId: widget.schoolId,
        schoolYear: widget.year,
        round: _round!,
        measure: _measure!,
        n: n,
        sectionId: _scope == _Scope.section ? _section!.id : null,
        grade: _scope == _Scope.grade ? _grade : null,
        asOf: DateTime.parse(_asOf),
      ),
      where: 'PhilIriRanking',
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _ranking = r;
    });
  }

  Future<void> _save(PhilIriRanking r) async {
    final name = 'Phil-IRI_ranking_${r.round.name}_${r.measure.name}_${widget.year}.csv';
    final path = await runAction(context, () => saveTextExport(name, philIriRankingCsv(r)), where: 'PhilIriRanking');
    if (path != null && mounted) await showSaved(context, path);
  }

  @override
  Widget build(BuildContext context) {
    final r = _ranking;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilterBar(children: [
          PhilIriRoundPicker(value: _round, onChanged: (v) => setState(() => _round = v)),
          BasaDropdown<PhilIriRankMeasure>(
            label: 'Measure',
            items: PhilIriRankMeasure.values,
            value: _measure,
            itemLabel: (m) => m.label,
            onChanged: (v) => setState(() => _measure = v),
          ),
          SegmentedButton<_Scope>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: _Scope.school, label: Text('Whole school')),
              ButtonSegment(value: _Scope.grade, label: Text('A grade')),
              ButtonSegment(value: _Scope.section, label: Text('A section')),
            ],
            selected: {_scope},
            onSelectionChanged: (s) => setState(() => _scope = s.first),
          ),
          if (_scope == _Scope.grade)
            BasaDropdown<int>(
              label: 'Grade',
              items: const [4, 5, 6, 7, 8, 9, 10],
              value: _grade,
              itemLabel: (g) => 'Grade $g',
              onChanged: (v) => setState(() => _grade = v),
            ),
          if (_scope == _Scope.section)
            SectionPicker(
              value: _section,
              reloadKey: '${widget.schoolId}-${widget.year}',
              where: (s) =>
                  s.schoolId == widget.schoolId && s.schoolYear == widget.year && (int.tryParse(s.gradeLevel) ?? 0) >= 4,
              onChanged: (s) => setState(() => _section = s),
            ),
          TextField(
            controller: _n,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'How many', prefixIcon: Icon(Icons.format_list_numbered)),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.event_outlined),
            label: Text('As of $_asOf'),
            onPressed: () async {
              final d = await pickDate(context, initial: _asOf);
              if (d != null && mounted) setState(() => _asOf = d);
            },
          ),
          FilledButton.icon(
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.leaderboard_outlined),
            label: const Text('Rank'),
            onPressed: _busy ? null : _rank,
          ),
        ]),
        const SizedBox(height: 16),
        if (r == null)
          const EmptyNote('Set the round, measure and scope, then Rank.', icon: Icons.leaderboard_outlined)
        else
          _RankingView(ranking: r, scopeText: _scopeText(r), onSave: () => _save(r)),
      ],
    );
  }

  String _scopeText(PhilIriRanking r) {
    if (r.sectionId != null) {
      final s = _section;
      return s != null && s.id == r.sectionId ? 'Grade ${s.gradeLevel} ${s.sectionName}' : 'section ${r.sectionId}';
    }
    if (r.grade != null) return 'Grade ${r.grade}';
    return 'whole school (Grades 4-10)';
  }
}

class _RankingView extends StatelessWidget {
  final PhilIriRanking ranking;
  final String scopeText;
  final VoidCallback onSave;
  const _RankingView({required this.ranking, required this.scopeText, required this.onSave});

  @override
  Widget build(BuildContext context) {
    final r = ranking;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    // philIriRankValueText gives the number only ("62.5", "48.0").
    final unit = r.measure == PhilIriRankMeasure.wpm ? ' wpm' : '%';
    final lastRank = r.ranked.isEmpty ? 0 : r.ranked.last.rank;
    final tiedAtLast = r.ranked.where((x) => x.rank == lastRank).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Text(
              '${r.round.label} · ${r.measure.label} · $scopeText · lowest ${r.n} · as of ${r.asOf}',
              style: theme.textTheme.titleMedium,
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.tonalIcon(onPressed: onSave, icon: const Icon(Icons.download), label: const Text('Save as CSV')),
        ]),
        const SizedBox(height: 12),
        ValuesNote(philIriValuesLabel(r.values)),
        const SizedBox(height: 12),
        if (r.tiedPastN) ...[
          NoticeBanner('${r.ranked.length} shown: $tiedAtLast tied at rank $lastRank.', tone: StatusTone.neutral),
          const SizedBox(height: 12),
        ],
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
              child: Row(children: [
                const IconBadge(Icons.leaderboard_outlined, size: 34),
                const SizedBox(width: 12),
                Expanded(child: Text('Ranked', style: theme.textTheme.titleMedium)),
                StatusChip('${r.ranked.length}', icon: Icons.table_rows_outlined),
              ]),
            ),
            if (r.ranked.isEmpty)
              const EmptyNote('No learner has a value for this measure in this round.', icon: Icons.leaderboard_outlined)
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor: WidgetStatePropertyAll(colors.surfaceContainerHigh),
                  dataRowMinHeight: 36,
                  dataRowMaxHeight: 52,
                  columnSpacing: 20,
                  columns: [
                    const DataColumn(label: Text('Rank'), numeric: true),
                    const DataColumn(label: Text('Learner')),
                    const DataColumn(label: Text('LRN')),
                    const DataColumn(label: Text('Grade'), numeric: true),
                    const DataColumn(label: Text('Section')),
                    DataColumn(label: Text(r.measure.label), numeric: true),
                    const DataColumn(label: Text('Profile')),
                  ],
                  rows: [
                    for (final x in r.ranked)
                      DataRow(cells: [
                        DataCell(Text('${x.rank}')),
                        DataCell(Text(x.name)),
                        DataCell(Text(x.student.lrn)),
                        DataCell(Text('${x.grade}')),
                        DataCell(Text(x.section.sectionName)),
                        DataCell(Text('${philIriRankValueText(r.measure, x.value)}$unit')),
                        DataCell(x.profile == null
                            ? const Text('—')
                            : StatusChip(x.profile!.label, tone: philIriLevelTone(x.profile))),
                      ]),
                  ],
                ),
              ),
          ]),
        ),
        const SizedBox(height: 16),
        ListCard(
          title: 'Not ranked',
          trailing: StatusChip('${r.unranked.length}'),
          children: [
            if (r.unranked.isEmpty)
              const EmptyNote('Every learner has a value for this measure.', icon: Icons.check_circle_outline)
            else
              for (final x in r.unranked)
                ListRow(
                  leading: LetterBadge(initialOf(x.name)),
                  title: x.name,
                  subtitle: 'LRN ${x.student.lrn} · Grade ${x.grade} ${x.section.sectionName}',
                  footer: StatusChip(x.reason.label, icon: Icons.info_outline),
                ),
          ],
        ),
      ],
    );
  }
}

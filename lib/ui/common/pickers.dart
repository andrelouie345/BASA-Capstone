// lib/ui/common/pickers.dart
// Choose a school, section, learner, ARAL class, school year, round or region
// by name (docs/handoff/screens/common.md, Pickers). Each picker loads its own
// list, shows loading / error / empty in place, and hands back the chosen
// item. Sections and learners come from this device's copy (work offline);
// schools need the server.
import 'package:flutter/material.dart';

import '../../core/models/aral_class.dart';
import '../../core/models/crla_assessment.dart';
import '../../core/models/phil_iri_assessment.dart';
import '../../core/models/region.dart';
import '../../core/models/school.dart';
import '../../core/models/section.dart';
import '../../core/models/student.dart';
import '../../viewmodels/app_viewmodels.dart';
import '../basa_scope.dart';
import 'error_display.dart';
import 'search.dart';

/// A dropdown over a fixed list.
class BasaDropdown<T> extends StatelessWidget {
  final String label;
  final List<T> items;
  final T? value;
  final String Function(T) itemLabel;
  final ValueChanged<T?>? onChanged;
  final String? hint;
  final bool allowNone;

  const BasaDropdown({
    super.key,
    required this.label,
    required this.items,
    required this.value,
    required this.itemLabel,
    required this.onChanged,
    this.hint,
    this.allowNone = false,
  });

  @override
  Widget build(BuildContext context) {
    // A value that is no longer in the list would assert; show nothing chosen.
    final current = items.contains(value) ? value : null;
    if (items.length > kSearchableThreshold) {
      return _SearchDropdown<T>(
        label: label,
        items: items,
        value: current,
        itemLabel: itemLabel,
        onChanged: onChanged,
        hint: hint,
        allowNone: allowNone,
      );
    }
    return DropdownButtonFormField<T>(
      // The field keeps its first value: a new value is a new field.
      key: ValueKey<Object?>(current),
      initialValue: current,
      isExpanded: true,
      decoration: InputDecoration(labelText: label, hintText: hint),
      items: [
        if (allowNone) DropdownMenuItem<T>(value: null, child: Text(hint ?? 'None')),
        for (final item in items)
          DropdownMenuItem<T>(
            value: item,
            child: Text(itemLabel(item), overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

/// A dropdown with a search box (long lists): typing filters on any part of
/// the label, arrow keys + Enter pick, Esc closes. The field shows the chosen
/// item again when it loses focus, so a half-typed search never changes it.
class _SearchDropdown<T> extends StatefulWidget {
  final String label;
  final List<T> items;
  final T? value;
  final String Function(T) itemLabel;
  final ValueChanged<T?>? onChanged;
  final String? hint;
  final bool allowNone;

  const _SearchDropdown({
    super.key,
    required this.label,
    required this.items,
    required this.value,
    required this.itemLabel,
    required this.onChanged,
    required this.hint,
    required this.allowNone,
  });

  @override
  State<_SearchDropdown<T>> createState() => _SearchDropdownState<T>();
}

class _SearchDropdownState<T> extends State<_SearchDropdown<T>> {
  late final _text = TextEditingController(text: _chosenLabel);
  final _focus = FocusNode();

  String get _chosenLabel {
    final v = widget.value;
    if (v != null) return widget.itemLabel(v);
    return widget.allowNone ? (widget.hint ?? 'None') : '';
  }

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && _text.text != _chosenLabel) _text.text = _chosenLabel;
    });
  }

  @override
  void didUpdateWidget(covariant _SearchDropdown<T> old) {
    super.didUpdateWidget(old);
    if (!identical(old.value, widget.value) && !_focus.hasFocus) _text.text = _chosenLabel;
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = [
      if (widget.allowNone) DropdownMenuEntry<T?>(value: null, label: widget.hint ?? 'None'),
      for (final item in widget.items) DropdownMenuEntry<T?>(value: item, label: widget.itemLabel(item)),
    ];
    return DropdownMenu<T?>(
      controller: _text,
      focusNode: _focus,
      initialSelection: widget.value,
      dropdownMenuEntries: entries,
      label: Text(widget.label),
      hintText: widget.hint,
      leadingIcon: const Icon(Icons.search),
      expandedInsets: EdgeInsets.zero,
      menuHeight: 360,
      enabled: widget.onChanged != null,
      // Phones too: tapping the field opens the keyboard for the search.
      requestFocusOnTap: true,
      enableFilter: true,
      filterCallback: (entries, query) {
        final shown = [for (final e in entries) if (matchesSearch(query, [e.label])) e];
        return shown.isNotEmpty ? shown : [DropdownMenuEntry<T?>(value: null, label: 'No matches', enabled: false)];
      },
      // Enter picks the first match (the default only finds labels that start with the text).
      searchCallback: (entries, query) {
        if (query.trim().isEmpty) return null;
        final i = entries.indexWhere((e) => e.enabled);
        return i < 0 ? null : i;
      },
      onSelected: (v) {
        // Enter with no match also reports null: only the None entry clears the choice.
        if (v == null && !(widget.allowNone && _text.text == (widget.hint ?? 'None'))) return;
        _focus.unfocus();
        widget.onChanged?.call(v);
      },
    );
  }
}

/// A dropdown whose list comes from a ViewModel call. [load] gets the
/// ViewModels (read before the call, so no context is used across an await).
/// The list reloads when [reloadKey] changes (e.g. a new section id).
class AsyncPicker<T> extends StatefulWidget {
  final String label;
  final Future<List<T>> Function(AppViewModels vms) load;
  final T? value;
  final String Function(T) itemLabel;
  final ValueChanged<T?> onChanged;
  final Object? reloadKey;
  final String emptyText;

  /// Two items are the same choice (models have no ==, so compare ids).
  final bool Function(T a, T b)? same;

  /// Pick the first item once the list is loaded and nothing is chosen.
  final bool pickFirst;

  const AsyncPicker({
    super.key,
    required this.label,
    required this.load,
    required this.value,
    required this.itemLabel,
    required this.onChanged,
    this.reloadKey,
    this.emptyText = 'Nothing to choose from yet.',
    this.same,
    this.pickFirst = false,
  });

  @override
  State<AsyncPicker<T>> createState() => _AsyncPickerState<T>();
}

class _AsyncPickerState<T> extends State<AsyncPicker<T>> {
  List<T>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didUpdateWidget(covariant AsyncPicker<T> old) {
    super.didUpdateWidget(old);
    // After this frame: a ViewModel logs at once, and the debug console redraws on every log line.
    if (old.reloadKey != widget.reloadKey) WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    final vms = BasaScope.of(context);
    setState(() {
      _items = null;
      _error = null;
    });
    try {
      final items = await widget.load(vms);
      if (!mounted) return;
      setState(() => _items = items);
      if (widget.pickFirst && widget.value == null && items.isNotEmpty) widget.onChanged(items.first);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessageFor(e, where: 'AsyncPicker(${widget.label})'));
    }
  }

  T? _match(List<T> items) {
    final v = widget.value;
    if (v == null) return null;
    final same = widget.same;
    for (final i in items) {
      if (same == null ? i == v : same(i, v)) return i;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    if (_error != null) return ErrorMessage(message: _error!, onRetry: _load);
    if (items == null) {
      return InputDecorator(
        decoration: InputDecoration(labelText: widget.label),
        child: const Align(
          alignment: Alignment.centerLeft,
          child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }
    if (items.isEmpty) {
      return InputDecorator(
        decoration: InputDecoration(labelText: widget.label, enabled: false),
        child: Text(widget.emptyText, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
    }
    return BasaDropdown<T>(
      label: widget.label,
      items: items,
      value: _match(items),
      itemLabel: widget.itemLabel,
      onChanged: widget.onChanged,
    );
  }
}

// ---- The pickers screens use ----

/// Schools the user may see (needs an online sign-in).
class SchoolPicker extends StatelessWidget {
  final School? value;
  final ValueChanged<School?> onChanged;
  final bool pickFirst;
  const SchoolPicker({super.key, required this.value, required this.onChanged, this.pickFirst = false});

  @override
  Widget build(BuildContext context) => AsyncPicker<School>(
    label: 'School',
    load: (vms) async {
      await vms.school.loadAll();
      return vms.school.items;
    },
    value: value,
    itemLabel: (s) => s.schoolName,
    same: (a, b) => a.id == b.id,
    onChanged: onChanged,
    pickFirst: pickFirst,
    emptyText: 'No schools you can see.',
  );
}

/// School names by id when this device holds sections of more than one school
/// (a superadmin's device); null when they are all one school's, so labels stay
/// short. A school list that can't be read leaves the names out (null).
Future<Map<int, String>?> schoolNamesIfSeveral(AppViewModels vms, [List<Section>? sections]) async {
  final all = sections ?? await vms.section.localSections();
  if (all.map((s) => s.schoolId).toSet().length < 2) return null;
  try {
    return {for (final s in await vms.school.localSchools()) if (s.id != null) s.id!: s.schoolName};
  } catch (_) {
    return null;
  }
}

String sectionLabel(Section s, [Map<int, String>? schoolNames]) {
  final school = schoolNames?[s.schoolId];
  return 'Grade ${s.gradeLevel} · ${s.sectionName} (${s.schoolYear})${school == null ? '' : ' · $school'}';
}

/// Sections on this device (works offline). [where] narrows the list,
/// e.g. one school year. Labels name the school when the device holds more
/// than one.
class SectionPicker extends StatefulWidget {
  final Section? value;
  final ValueChanged<Section?> onChanged;
  final bool Function(Section)? where;
  final Object? reloadKey;
  final bool pickFirst;
  const SectionPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.where,
    this.reloadKey,
    this.pickFirst = false,
  });

  @override
  State<SectionPicker> createState() => _SectionPickerState();
}

class _SectionPickerState extends State<SectionPicker> {
  // Set by load before AsyncPicker shows the list; itemLabel reads it then.
  Map<int, String>? _schoolNames;

  @override
  Widget build(BuildContext context) => AsyncPicker<Section>(
    label: 'Section',
    load: (vms) async {
      final all = await vms.section.localSections();
      _schoolNames = await schoolNamesIfSeveral(vms, all);
      final where = widget.where;
      return where == null ? all : all.where(where).toList();
    },
    value: widget.value,
    itemLabel: (s) => sectionLabel(s, _schoolNames),
    same: (a, b) => a.id == b.id,
    onChanged: widget.onChanged,
    reloadKey: widget.reloadKey,
    pickFirst: widget.pickFirst,
    emptyText: 'No sections on this device. Download the latest data first.',
  );
}

String studentLabel(Student s) =>
    [s.lastName, s.firstName].where((p) => p.isNotEmpty).join(', ') + (s.lrn.isEmpty ? '' : '  ·  ${s.lrn}');

/// Learners of one section, from this device's copy (works offline).
/// [schoolName], when given, is added to each label (see [schoolNamesIfSeveral]).
class StudentPicker extends StatelessWidget {
  final int sectionId;
  final Student? value;
  final ValueChanged<Student?> onChanged;
  final String? schoolName;
  const StudentPicker(
      {super.key, required this.sectionId, required this.value, required this.onChanged, this.schoolName});

  @override
  Widget build(BuildContext context) => AsyncPicker<Student>(
    label: 'Learner',
    load: (vms) => vms.student.localStudents(sectionId),
    value: value,
    itemLabel: (s) => schoolName == null ? studentLabel(s) : '${studentLabel(s)}  ·  $schoolName',
    same: (a, b) => a.lrn == b.lrn,
    onChanged: onChanged,
    reloadKey: sectionId,
    emptyText: 'No learners in this section on this device.',
  );
}

/// ARAL classes of a school (and school year).
class AralClassPicker extends StatelessWidget {
  final int schoolId;
  final String? schoolYear;
  final AralClass? value;
  final ValueChanged<AralClass?> onChanged;
  const AralClassPicker({
    super.key,
    required this.schoolId,
    this.schoolYear,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => AsyncPicker<AralClass>(
    label: 'ARAL class',
    load: (vms) => vms.aralClass.classes(schoolId: schoolId, schoolYear: schoolYear),
    value: value,
    itemLabel: (c) => '${c.className} · Grade ${c.gradeLevel}',
    same: (a, b) => a.id == b.id,
    onChanged: onChanged,
    reloadKey: Object.hash(schoolId, schoolYear),
    emptyText: 'No ARAL classes yet.',
  );
}

/// School years on this device, latest first.
class SchoolYearPicker extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool pickFirst;
  const SchoolYearPicker({super.key, required this.value, required this.onChanged, this.pickFirst = true});

  @override
  Widget build(BuildContext context) => AsyncPicker<String>(
    label: 'School year',
    load: (vms) => vms.dashboard.schoolYears(),
    value: value,
    itemLabel: (y) => y,
    onChanged: onChanged,
    pickFirst: pickFirst,
    emptyText: 'No school years on this device yet. Download the latest data first.',
  );
}

class PhilIriRoundPicker extends StatelessWidget {
  final PhilIriRound? value;
  final ValueChanged<PhilIriRound?> onChanged;
  const PhilIriRoundPicker({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => BasaDropdown<PhilIriRound>(
    label: 'Round',
    items: PhilIriRound.values,
    value: value,
    itemLabel: (r) => r.label,
    onChanged: onChanged,
  );
}

class CrlaRoundPicker extends StatelessWidget {
  final CrlaRound? value;
  final ValueChanged<CrlaRound?> onChanged;
  const CrlaRoundPicker({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => BasaDropdown<CrlaRound>(
    label: 'Round',
    items: CrlaRound.values,
    value: value,
    itemLabel: (r) => r.label,
    onChanged: onChanged,
  );
}

class RegionPicker extends StatelessWidget {
  final Region? value;
  final ValueChanged<Region?> onChanged;
  const RegionPicker({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => BasaDropdown<Region>(
    label: 'Region',
    items: Region.all,
    value: value == null ? null : Region.byId(value!.id),
    itemLabel: (r) => '${r.code} · ${r.name}',
    onChanged: onChanged,
  );
}

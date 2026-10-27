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
    if (old.reloadKey != widget.reloadKey) _load();
  }

  Future<void> _load() async {
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

/// Sections on this device (works offline). [where] narrows the list,
/// e.g. one school year.
class SectionPicker extends StatelessWidget {
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
  Widget build(BuildContext context) => AsyncPicker<Section>(
    label: 'Section',
    load: (vms) async {
      final all = await vms.section.localSections();
      return where == null ? all : all.where(where!).toList();
    },
    value: value,
    itemLabel: (s) => 'Grade ${s.gradeLevel} · ${s.sectionName} (${s.schoolYear})',
    same: (a, b) => a.id == b.id,
    onChanged: onChanged,
    reloadKey: reloadKey,
    pickFirst: pickFirst,
    emptyText: 'No sections on this device. Download the latest data first.',
  );
}

String studentLabel(Student s) =>
    [s.lastName, s.firstName].where((p) => p.isNotEmpty).join(', ') + (s.lrn.isEmpty ? '' : '  ·  ${s.lrn}');

/// Learners of one section, from this device's copy (works offline).
class StudentPicker extends StatelessWidget {
  final int sectionId;
  final Student? value;
  final ValueChanged<Student?> onChanged;
  const StudentPicker({super.key, required this.sectionId, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => AsyncPicker<Student>(
    label: 'Learner',
    load: (vms) => vms.student.localStudents(sectionId),
    value: value,
    itemLabel: studentLabel,
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

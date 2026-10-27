// lib/ui/common/school_year_scope.dart
// The school and school year a report is for: the user's own school (a
// superadmin picks one) and a year picked from this device's years. The
// child is built once both are known.
import 'package:flutter/material.dart';

import '../../core/models/school.dart';
import 'pickers.dart';
import 'screen_kit.dart';

class SchoolYearScope extends StatefulWidget {
  final Widget Function(BuildContext context, int schoolId, String year) builder;
  const SchoolYearScope({super.key, required this.builder});

  @override
  State<SchoolYearScope> createState() => _SchoolYearScopeState();
}

class _SchoolYearScopeState extends State<SchoolYearScope> {
  School? _school;
  String? _year;

  @override
  Widget build(BuildContext context) {
    final own = vmsOf(context).auth.currentUser?.schoolId;
    final schoolId = own ?? _school?.id;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (own == null) ...[
          SchoolPicker(value: _school, onChanged: (s) => setState(() => _school = s)),
          const SizedBox(height: 12),
        ],
        SchoolYearPicker(value: _year, onChanged: (y) => setState(() => _year = y)),
        const SizedBox(height: 12),
        if (schoolId != null && _year != null) widget.builder(context, schoolId, _year!),
      ],
    );
  }
}

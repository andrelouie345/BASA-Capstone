// lib/ui/aral/aral_settings_screen.dart
// ARAL settings (docs/handoff/screens/aral.md): the check-in cut-off, SHARP
// (the foundational program), KS1 extended and idle-session days, each with
// the region and school layers; and the school ARAL rules (Division
// Memorandum 180 s. 2026: class size, sessions, basis round, check-ins, IRIP,
// advisers, daily tutor limits). Changing them is admin-only: the admin build
// passes an [AralSettingsEditor] (lib/ui/admin/).
import 'package:flutter/material.dart';

import '../../core/models/aral_types.dart' show AralRuleSettings;
import '../../viewmodels/aral_checkin_viewmodel.dart';
import '../common/screen_kit.dart';

/// Which setting a change is for.
enum AralSettingKey { passPct, sharp, ks1Extended, idleDays }

/// The admin build's settings changes. Each returns true when something changed.
abstract class AralSettingsEditor {
  const AralSettingsEditor();
  bool canEdit(BuildContext context);
  Future<bool> change(BuildContext context, int? schoolId, AralSettingKey key, Object current);
  Future<bool> reset(BuildContext context, int schoolId);

  /// One school ARAL rule ([AralRuleSettings.keys]); [current] = the value in
  /// force. True when it changed.
  Future<bool> changeRule(BuildContext context, int? schoolId, String key, Object? current);
}

/// The school ARAL rules, in order, with the words a screen shows.
const aralRuleLabels = {
  'class_max_learners': 'Class maximum',
  'class_min_learners': 'Class minimum (0 = none)',
  'session_max_minutes': 'Longest session (minutes)',
  'sessions_weekdays_only': 'Weekdays only',
  'class_min_sessions_per_week': 'Sessions a week (at least)',
  'basis_round': 'Choose new learners from',
  'checkin_after_sessions': 'Check-ins after sessions',
  'irip_weeks': 'IRIP weeks',
  'internal_tutor_max_sessions_per_day': 'Internal tutor: sessions a day',
  'external_tutor_max_minutes_per_day': 'External tutor: minutes a day',
  'adviser_tutors_own_class': 'Advisers tutor their own learners',
};

/// A rule's value as a screen shows it; null = not set.
String aralRuleText(Object? v, {String none = '—'}) => switch (v) {
  null => none,
  true => 'on',
  false => 'off',
  'bosy' => 'BoSY',
  'mosy' => 'MoSY',
  List l => l.join(', '),
  _ => '$v',
};

/// One rule: the stored region and school values, the one in force and the
/// default. [local] = read from this device's copy (offline): no layers.
typedef _Rule = ({String key, Object? region, Object? school, Object? effective, Object? defaults});

class _Rules {
  final List<_Rule> rules;
  final bool local;
  const _Rules(this.rules, this.local);
}

class _Layers {
  final AralCheckinSettingLayers pass;
  final ({bool? region, bool? school, bool effective, bool defaults}) sharp;
  final ({bool? region, bool? school, bool effective, bool defaults}) ks1;
  final ({int? region, int? school, int effective, int defaults}) idle;
  const _Layers(this.pass, this.sharp, this.ks1, this.idle);
}

class AralSettingsScreen extends StatefulWidget {
  final AralSettingsEditor? editor;
  const AralSettingsScreen({super.key, this.editor});

  @override
  State<AralSettingsScreen> createState() => _AralSettingsScreenState();
}

class _AralSettingsScreenState extends State<AralSettingsScreen> {
  int _reload = 0;

  Future<void> _after(Future<bool> change) async {
    if (await change && mounted) setState(() => _reload++);
  }

  @override
  Widget build(BuildContext context) {
    final schoolId = vmsOf(context).auth.currentUser?.schoolId;
    final editor = widget.editor;
    final canEdit = editor != null && editor.canEdit(context);
    String yesNo(bool? b) => b == null ? '—' : (b ? 'on' : 'off');
    return Scaffold(
      appBar: AppBar(title: const Text('ARAL settings')),
      body: PageBody(
        children: [
          LoadView<_Layers>(
            where: 'AralSettings',
            reloadKey: _reload,
            load: (vms) async {
              final c = vms.aralCheckin;
              return _Layers(
                await c.settingLayers(schoolId),
                await c.foundationalProgramLayers(schoolId),
                await c.ks1ExtendedLayers(schoolId),
                await c.idleSessionDaysLayers(schoolId),
              );
            },
            builder: (context, l, _) {
              Widget row(
                IconData icon,
                String title,
                String effective,
                String region,
                String school,
                AralSettingKey key,
                Object current,
              ) => ListRow(
                leading: IconBadge(icon),
                title: title,
                subtitle: 'Region: $region · School: $school',
                trailing: [
                  StatusChip(effective, tone: effective == 'on' ? StatusTone.good : StatusTone.neutral),
                  if (canEdit)
                    IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () => _after(editor.change(context, schoolId, key, current)),
                    ),
                ],
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  NoticeBanner(
                    schoolId == null ? 'Region defaults.' : 'In force at your school.',
                    icon: schoolId == null ? Icons.public : Icons.school_outlined,
                    tone: StatusTone.neutral,
                  ),
                  const SizedBox(height: 12),
                  StatGrid(
                    tileWidth: 200,
                    tiles: [
                      StatTile(
                        label: 'Check-in cut-off',
                        value: '${l.pass.effective.passPct}%',
                        icon: Icons.fact_check_outlined,
                      ),
                      StatTile(label: 'SHARP', value: yesNo(l.sharp.effective), icon: Icons.auto_stories_outlined),
                      StatTile(label: 'KS1 extended', value: yesNo(l.ks1.effective), icon: Icons.child_care),
                      StatTile(label: 'Idle-session days', value: '${l.idle.effective}', icon: Icons.hourglass_empty),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ListCard(
                    title: 'Settings',
                    trailing: canEdit && schoolId != null
                        ? OutlinedButton.icon(
                            onPressed: () => _after(editor.reset(context, schoolId)),
                            icon: const Icon(Icons.restart_alt),
                            label: const Text("Use the region's settings"),
                          )
                        : null,
                    children: [
                      row(
                        Icons.fact_check_outlined,
                        'Check-in cut-off',
                        '${l.pass.effective.passPct}%',
                        '${l.pass.region?.settings['checkin_pass_pct'] ?? '—'}',
                        '${l.pass.school?.settings['checkin_pass_pct'] ?? '—'}',
                        AralSettingKey.passPct,
                        l.pass.effective.passPct,
                      ),
                      row(
                        Icons.auto_stories_outlined,
                        'SHARP (foundational program)',
                        yesNo(l.sharp.effective),
                        yesNo(l.sharp.region),
                        yesNo(l.sharp.school),
                        AralSettingKey.sharp,
                        l.sharp.effective,
                      ),
                      row(
                        Icons.child_care,
                        'KS1 extended',
                        yesNo(l.ks1.effective),
                        yesNo(l.ks1.region),
                        yesNo(l.ks1.school),
                        AralSettingKey.ks1Extended,
                        l.ks1.effective,
                      ),
                      row(
                        Icons.hourglass_empty,
                        'Idle-session reminder (days)',
                        '${l.idle.effective}',
                        '${l.idle.region ?? '—'}',
                        '${l.idle.school ?? '—'}',
                        AralSettingKey.idleDays,
                        l.idle.effective,
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
          _RulesCard(schoolId: schoolId, editor: canEdit ? editor : null, reloadKey: _reload, onChanged: _after),
        ],
      ),
    );
  }
}

/// The school ARAL rules (ARAL memo settings): the server's layers, or this
/// device's copy when the server can't be reached.
class _RulesCard extends StatelessWidget {
  final int? schoolId;
  final AralSettingsEditor? editor;
  final Object reloadKey;
  final Future<void> Function(Future<bool>) onChanged;
  const _RulesCard({required this.schoolId, required this.editor, required this.reloadKey, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return LoadView<_Rules>(
      where: 'AralRules',
      reloadKey: reloadKey,
      load: (vms) async {
        final c = vms.aralCheckin;
        try {
          return _Rules([
            for (final k in AralRuleSettings.keys)
              await c
                  .ruleSettingLayers(k, schoolId)
                  .then(
                    (l) => (key: k, region: l.region, school: l.school, effective: l.effective, defaults: l.defaults),
                  ),
          ], false);
        } catch (e) {
          final id = schoolId;
          if (id == null) rethrow;
          debugPrint('AralRules: server not reached, showing the device copy: $e');
          final local = await c.localRuleSettings(id);
          return _Rules([
            for (final k in AralRuleSettings.keys)
              (
                key: k,
                region: null,
                school: null,
                effective: local.valueOf(k),
                defaults: AralRuleSettings.defaults.valueOf(k),
              ),
          ], true);
        }
      },
      builder: (context, r, _) => ListCard(
        title: 'School ARAL rules',
        children: [
          NoticeBanner(
            r.local
                ? "Showing this device's copy (the server could not be reached). Download the latest data to update it."
                : 'DepEd and the Division change these numbers from time to time. A rule your school never set works as it always has.',
            icon: r.local ? Icons.cloud_off_outlined : Icons.rule,
            tone: r.local ? StatusTone.warn : StatusTone.neutral,
          ),
          for (final x in r.rules)
            ListRow(
              leading: const IconBadge(Icons.rule),
              title: aralRuleLabels[x.key] ?? x.key,
              subtitle: r.local
                  ? 'Default: ${aralRuleText(x.defaults, none: 'not set')}'
                  : 'Region: ${aralRuleText(x.region)} · School: ${aralRuleText(x.school)} · '
                        'Default: ${aralRuleText(x.defaults, none: 'not set')}',
              trailing: [
                StatusChip(
                  aralRuleText(x.effective, none: 'not set'),
                  tone: x.school != null ? StatusTone.good : StatusTone.neutral,
                ),
                if (editor != null && !r.local)
                  IconButton(
                    tooltip: 'Change',
                    icon: const Icon(Icons.edit),
                    onPressed: () => onChanged(editor!.changeRule(context, schoolId, x.key, x.effective)),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

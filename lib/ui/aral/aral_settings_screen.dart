// lib/ui/aral/aral_settings_screen.dart
// ARAL settings (docs/handoff/screens/aral.md): the check-in cut-off, SHARP
// (the foundational program), KS1 extended and idle-session days, each with
// the region and school layers. Changing them is admin-only: the admin build
// passes an [AralSettingsEditor] (lib/ui/admin/).
import 'package:flutter/material.dart';

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
      body: LoadView<_Layers>(
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
          Widget row(IconData icon, String title, String effective, String region, String school, AralSettingKey key, Object current) =>
              ListRow(
                leading: IconBadge(icon),
                title: title,
                subtitle: 'Region: $region · School: $school',
                trailing: [
                  StatusChip(effective, tone: effective == 'on' ? StatusTone.good : StatusTone.neutral),
                  if (canEdit)
                    IconButton(icon: const Icon(Icons.edit), onPressed: () => _after(editor.change(context, schoolId, key, current))),
                ],
              );
          return PageBody(
            children: [
              NoticeBanner(
                schoolId == null ? 'Region defaults.' : 'In force at your school.',
                icon: schoolId == null ? Icons.public : Icons.school_outlined,
                tone: StatusTone.neutral,
              ),
              StatGrid(tileWidth: 200, tiles: [
                StatTile(label: 'Check-in cut-off', value: '${l.pass.effective.passPct}%', icon: Icons.fact_check_outlined),
                StatTile(label: 'SHARP', value: yesNo(l.sharp.effective), icon: Icons.auto_stories_outlined),
                StatTile(label: 'KS1 extended', value: yesNo(l.ks1.effective), icon: Icons.child_care),
                StatTile(label: 'Idle-session days', value: '${l.idle.effective}', icon: Icons.hourglass_empty),
              ]),
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
                  row(Icons.fact_check_outlined, 'Check-in cut-off', '${l.pass.effective.passPct}%',
                      '${l.pass.region?.settings['checkin_pass_pct'] ?? '—'}', '${l.pass.school?.settings['checkin_pass_pct'] ?? '—'}',
                      AralSettingKey.passPct, l.pass.effective.passPct),
                  row(Icons.auto_stories_outlined, 'SHARP (foundational program)', yesNo(l.sharp.effective), yesNo(l.sharp.region),
                      yesNo(l.sharp.school), AralSettingKey.sharp, l.sharp.effective),
                  row(Icons.child_care, 'KS1 extended', yesNo(l.ks1.effective), yesNo(l.ks1.region), yesNo(l.ks1.school),
                      AralSettingKey.ks1Extended, l.ks1.effective),
                  row(Icons.hourglass_empty, 'Idle-session reminder (days)', '${l.idle.effective}', '${l.idle.region ?? '—'}',
                      '${l.idle.school ?? '—'}', AralSettingKey.idleDays, l.idle.effective),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

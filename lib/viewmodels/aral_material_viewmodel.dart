// lib/viewmodels/aral_material_viewmodel.dart
//
// ARAL learning materials (piece R3a): the catalog and the recommendations.
//
// Reading coordinator (2026-10-18):
//  * Recommendations exist only in ARAL, for learners on the roster: a
//    learner gets the active materials of their ARAL program (key stage +
//    track; a material without a track fits either track) that are meant for
//    their grade. The program already follows her bands (aralPhilIriPlacement),
//    so materials and placement agree.
//  * The ARAL KS1-KS3 materials are for Grades 7-10; Grades 1-6 get nothing
//    for now (she may get files for them later).
//  * Foundational (SHARP) materials only while the school's foundational
//    literacy program is switched on.
//  * Materials work offline: the files come with piece R3b.
// The catalog is managed online (superadmin: region-wide; admin/coordinator:
// their own school's) and mirrored to this device; recommendations are read
// from the local copy, so they work offline.
import 'package:supabase/supabase.dart' show PostgrestException, SupabaseClient;

import '../core/console/logger.dart';
import '../core/models/aral_enrollment.dart';
import '../core/models/aral_material.dart';
import '../core/models/user.dart';
import '../core/models/user_role.dart';
import '../core/repositories/aral_enrollment_repository.dart';
import '../core/repositories/aral_material_repository.dart';
import '../core/repositories/aral_setting_repository.dart';
import '../core/repositories/section_repository.dart';
import '../core/services/aral_rules.dart' show AralProgramSettings;
import 'auth_viewmodel.dart';
import 'viewmodel_exception.dart';

/// The materials one ARAL learner gets.
class AralRecommendation {
  final AralEnrollment enrollment;
  final int grade;
  final List<AralMaterial> materials;
  /// Why the list is empty or shorter than expected (null when nothing to say).
  final String? note;

  const AralRecommendation(this.enrollment, this.grade, this.materials, this.note);
}

class AralMaterialViewModel {
  final ScopedLogger _log;
  final AuthViewModel _auth;
  final AralMaterialRepository _local;
  final AralMaterialRepository Function(SupabaseClient client) _cloudFor;
  final AralEnrollmentRepository _roster;
  final SectionRepository _sections;
  final AralSettingRepository _localSettings;

  /// Set when the last catalog change reached the cloud but its local copy failed.
  String? lastMirrorWarning;

  AralMaterialViewModel({
    required AuthViewModel auth,
    required AralMaterialRepository local,
    required AralMaterialRepository Function(SupabaseClient client) cloud,
    required AralEnrollmentRepository roster,
    required SectionRepository sections,
    required AralSettingRepository localSettings,
    Logger? logger,
  })  : _auth = auth,
        _local = local,
        _cloudFor = cloud,
        _roster = roster,
        _sections = sections,
        _localSettings = localSettings,
        _log = ScopedLogger(logger, 'AralMaterialViewModel');

  // ---- Catalog ----

  /// The catalog on this device (region-wide + the user's school; pull-cloud refreshes it).
  Future<List<AralMaterial>> catalog({bool activeOnly = false}) {
    _log('catalog(activeOnly: $activeOnly)');
    return _local.getAll(activeOnly: activeOnly);
  }

  Future<AralMaterial> material(int id) async {
    final m = await _local.findById(id);
    if (m == null) throw ViewModelException('No ARAL material with id $id on this device (run pull-cloud).');
    return m;
  }

  /// Adds a material: region-wide ([schoolId] null, superadmin) or for a school
  /// (its admin/coordinator). Online; mirrored to this device.
  Future<AralMaterial> addMaterial({
    int? schoolId,
    required String title,
    required AralKeyStage keyStage,
    AralTrack? track,
    AralMaterialKind kind = AralMaterialKind.learner,
    String language = 'English',
    int minGrade = aralMaterialDefaultMinGrade,
    int maxGrade = aralMaterialDefaultMaxGrade,
    String? description,
  }) async {
    _log('addMaterial(school: $schoolId, "$title", ${keyStage.name} ${track?.name}, ${kind.name}, $language, '
        'grades $minGrade-$maxGrade)');
    final cloud = _writer(schoolId);
    final m = _checked(AralMaterial(
      schoolId: schoolId,
      title: title.trim(),
      description: _blankToNull(description),
      keyStage: keyStage,
      track: track,
      kind: kind,
      language: language,
      minGrade: minGrade,
      maxGrade: maxGrade,
    ));
    final saved = await _cloudWrite(() => cloud.insert(m));
    await _mirror(() => _local.upsertWithId(saved));
    return saved;
  }

  /// Changes a material's details (not its owner). Online; mirrored.
  Future<AralMaterial> updateMaterial(
    int id, {
    String? title,
    String? Function()? description,
    AralKeyStage? keyStage,
    AralTrack? Function()? track,
    AralMaterialKind? kind,
    String? language,
    int? minGrade,
    int? maxGrade,
  }) async {
    _log('updateMaterial($id)');
    final (cloud, current) = await _writable(id);
    final m = _checked(current.copyWith(
      title: title?.trim(),
      description: description == null ? null : () => _blankToNull(description()),
      keyStage: keyStage,
      track: track,
      kind: kind,
      language: language,
      minGrade: minGrade,
      maxGrade: maxGrade,
    ));
    final saved = await _cloudWrite(() => cloud.update(m));
    await _mirror(() => _local.upsertWithId(saved));
    return saved;
  }

  /// Retires a material (it stays in the catalog, no longer recommended) or brings it back.
  Future<AralMaterial> setActive(int id, bool active) async {
    _log('setActive($id, $active)');
    final (cloud, current) = await _writable(id);
    final saved = await _cloudWrite(() => cloud.update(current.copyWith(isActive: active)));
    await _mirror(() => _local.upsertWithId(saved));
    return saved;
  }

  /// Removes a material from the catalog. Online; the local copy goes too.
  Future<void> deleteMaterial(int id) async {
    _log('deleteMaterial($id)');
    final (cloud, _) = await _writable(id);
    await _cloudWrite(() => cloud.delete(id));
    await _mirror(() => _local.removeMirrored(id));
  }

  // ---- Recommendations (offline) ----

  /// The materials for one ARAL learner: their tutor, or an admin/coordinator
  /// of their school (any school for the superadmin).
  Future<AralRecommendation> recommendations(int enrollmentId) async {
    _log('recommendations($enrollmentId)');
    final e = await _requireLearner(enrollmentId);
    return _recommend(e, await _localCatalog());
  }

  /// Every active ARAL learner of a section (admin/coordinator).
  Future<List<AralRecommendation>> sectionRecommendations({required int sectionId, required String schoolYear}) async {
    _log('sectionRecommendations(section: $sectionId, year: $schoolYear)');
    final me = _me();
    if (me.role != UserRole.admin && me.role != UserRole.coordinator) {
      throw const ViewModelException('Forbidden: admin or coordinator only.');
    }
    final section = await _sections.getById(sectionId);
    if (section == null) throw ViewModelException('No section with id $sectionId.');
    if (me.schoolId != null && me.schoolId != section.schoolId) {
      throw const ViewModelException('Forbidden: that section is in another school.');
    }
    final catalog = await _localCatalog();
    final out = <AralRecommendation>[];
    for (final e in (await _roster.getBySection(sectionId, schoolYear: schoolYear)).where((e) => e.isActive)) {
      out.add(await _recommend(e, catalog));
    }
    return out;
  }

  Future<List<AralMaterial>> _localCatalog() => _local.getAll(activeOnly: true);

  Future<AralRecommendation> _recommend(AralEnrollment e, List<AralMaterial> catalog) async {
    final section = await _sections.getById(e.sectionId);
    final grade = int.tryParse(section?.gradeLevel ?? '') ?? 0;
    final program = await _programSettings(e.schoolId);
    if (e.keyStage == AralKeyStage.foundational && !program.foundationalProgram) {
      return AralRecommendation(e, grade, const [],
          'The foundational literacy program (SHARP) is switched off for this school: run aral-update to move '
          'the learner to KS1.');
    }
    final list = catalog
        .where((m) => (m.schoolId == null || m.schoolId == e.schoolId) && m.fits(e.keyStage, e.track, grade))
        .toList()
      ..sort((a, b) {
        final k = a.kind.index.compareTo(b.kind.index);
        return k != 0 ? k : a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
    String? note;
    if (list.isEmpty) {
      note = grade < aralMaterialDefaultMinGrade
          ? 'No ARAL materials for Grade $grade learners yet (the ARAL materials are for Grades 7-10).'
          : 'No active ${e.programLabel} materials for Grade $grade in the catalog on this device '
              '(add some, or run pull-cloud).';
    }
    return AralRecommendation(e, grade, list, note);
  }

  Future<AralProgramSettings> _programSettings(int schoolId) async {
    final region = await _localSettings.getRegion();
    final school = await _localSettings.getForSchool(schoolId);
    return AralProgramSettings.fromMap({...?region?.settings, ...?school?.settings});
  }

  // ---- helpers ----

  User _me() {
    final u = _auth.currentUser;
    if (u == null) throw const ViewModelException('Not signed in.');
    return u;
  }

  /// The learner's ARAL tutor, or an admin/coordinator of the learner's
  /// school (any school for the superadmin).
  Future<AralEnrollment> _requireLearner(int enrollmentId) async {
    final e = await _roster.findById(enrollmentId);
    if (e == null) throw ViewModelException('No ARAL enrollment with id $enrollmentId.');
    final me = _me();
    if (me.role == UserRole.tutor) {
      if (e.tutorId != me.id) throw const ViewModelException('Forbidden: not your ARAL learner.');
    } else if (me.role == UserRole.admin || me.role == UserRole.coordinator) {
      if (me.schoolId != null && me.schoolId != e.schoolId) {
        throw const ViewModelException('Forbidden: that learner is in another school.');
      }
    } else {
      throw const ViewModelException('Forbidden.');
    }
    return e;
  }

  /// The cloud repository for writing [schoolId]'s materials (null = region-wide).
  AralMaterialRepository _writer(int? schoolId) {
    final sessionError = _auth.requireActiveSession();
    if (sessionError != null) throw ViewModelException(sessionError);
    final me = _me();
    if (me.role != UserRole.admin && me.role != UserRole.coordinator) {
      throw const ViewModelException('Forbidden: admin or coordinator only.');
    }
    final superadmin = me.role == UserRole.admin && me.schoolId == null;
    if (!superadmin) {
      if (schoolId == null) {
        throw const ViewModelException('Forbidden: only the superadmin manages region-wide materials.');
      }
      if (me.schoolId != schoolId) {
        throw const ViewModelException("Forbidden: you can only manage your own school's materials.");
      }
    }
    lastMirrorWarning = null;
    return _cloudFor(_auth.client!);
  }

  Future<(AralMaterialRepository, AralMaterial)> _writable(int id) async {
    final current = await material(id);
    return (_writer(current.schoolId), current);
  }

  /// The same rules as the cloud CHECKs, with readable messages.
  AralMaterial _checked(AralMaterial m) {
    if (m.title.trim().isEmpty) throw const ViewModelException('Give the material a title.');
    if (!m.keyStage.hasTrack && m.track != null) {
      throw ViewModelException('${m.keyStage.label} has no Basic/Plus track.');
    }
    if (!aralMaterialLanguages.contains(m.language)) {
      throw ViewModelException('Language is ${aralMaterialLanguages.join(' or ')} (got "${m.language}").');
    }
    if (m.minGrade < 1 || m.maxGrade > 12 || m.minGrade > m.maxGrade) {
      throw ViewModelException('Grades must be within 1-12, lowest first (got ${m.minGrade}-${m.maxGrade}).');
    }
    if (m.keyStage == AralKeyStage.ks3 && m.minGrade < 7) {
      throw const ViewModelException('KS3 materials are for Grades 7-10 only.');
    }
    return m;
  }

  Future<T> _cloudWrite<T>(Future<T> Function() write) async {
    try {
      return await write();
    } on PostgrestException catch (e) {
      if (e.code == '42501') throw const ViewModelException('Forbidden: the database refused this change.');
      if (e.code == '23505') throw const ViewModelException('A material with that title already exists here.');
      if (e.code == '23514') throw ViewModelException('The database refused the values (${e.message}).');
      rethrow;
    }
  }

  Future<void> _mirror(Future<void> Function() write) async {
    try {
      await write();
    } catch (e) {
      lastMirrorWarning = 'The catalog was changed online, but the local copy was not updated ($e). Run pull-cloud.';
      _log('WARNING: $lastMirrorWarning');
    }
  }

  static String? _blankToNull(String? s) => s == null || s.trim().isEmpty ? null : s.trim();
}

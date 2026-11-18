// lib/viewmodels/section_viewmodel.dart
import 'package:supabase/supabase.dart';
import '../core/console/logger.dart';
import '../core/models/section.dart';
import '../core/models/user_role.dart';
import '../core/repositories/section_repository.dart';
import '../core/repositories/user_repository.dart';
import '../core/services/normalizers.dart';
import 'auth_viewmodel.dart';
import 'viewmodel_exception.dart';

/// Sections, read and written through the signed-in user's client (RLS
/// applies). Writes: superadmin any school, admin/coordinator their own.
/// School year and grade level are normalized here, so every caller stores
/// the same canonical values (see normalizers.dart).
///
/// [localSections] reads this device's copy instead (works offline).
class SectionViewModel {
  final ScopedLogger _log;
  final AuthViewModel _auth;
  final SectionRepository Function(SupabaseClient client) _repoFor;
  final SectionRepository? _local;
  final UserRepository Function(SupabaseClient client)? _usersFor;
  List<Section> items = [];

  /// Set when an adviser was saved online but not copied onto this device.
  String? lastMirrorWarning;

  SectionViewModel({
    required AuthViewModel auth,
    required SectionRepository Function(SupabaseClient client) repoFactory,
    SectionRepository? local,
    UserRepository Function(SupabaseClient client)? userRepoFactory,
    Logger? logger,
  })  : _auth = auth,
        _repoFor = repoFactory,
        _usersFor = userRepoFactory,
        _local = local,
        _log = ScopedLogger(logger, 'SectionViewModel');

  /// The sections on this device (what the last pull gave the device owner,
  /// plus sections created here). Online or offline sign-in.
  Future<List<Section>> localSections() async {
    _log('localSections()');
    final sessionError = _auth.requireActiveSession();
    if (sessionError != null) throw ViewModelException(sessionError);
    final local = _local;
    if (local == null) throw const ViewModelException('No local copy on this device.');
    return local.getAll();
  }

  SectionRepository _repo() {
    final sessionError = _auth.requireOnlineSession();
    if (sessionError != null) throw ViewModelException(sessionError);
    return _repoFor(_auth.client!);
  }

  void _checkCanManage(int schoolId) {
    final user = _auth.currentUser;
    if (user?.role == UserRole.admin && user?.schoolId == null) return; // superadmin
    if (user?.role != UserRole.admin && user?.role != UserRole.coordinator) {
      throw const ViewModelException('Not allowed: admin or coordinator only.');
    }
    if (user?.schoolId != schoolId) {
      throw const ViewModelException('Not allowed: can only manage sections for your own school.');
    }
  }

  /// Every section the user may see (tutors: their assigned sections).
  Future<void> loadAll() async {
    _log('loadAll()');
    items = await _repo().getAll();
  }

  /// Null when the section doesn't exist or isn't visible to the user.
  Future<Section?> getById(int id) async {
    _log('getById($id)');
    return _repo().getById(id);
  }

  /// Returns the existing section (created: false) when one with the same
  /// school, year, grade and name is already stored.
  Future<({Section section, bool created})> create({
    required int schoolId,
    required String schoolYear,
    required String gradeLevel,
    required String sectionName,
  }) async {
    _log('create(schoolId: $schoolId, year: "$schoolYear", grade: "$gradeLevel", name: "$sectionName")');
    final repo = _repo();
    _checkCanManage(schoolId);
    final wanted = Section(
      schoolId: schoolId,
      schoolYear: _normalize(normalizeSchoolYear, schoolYear),
      gradeLevel: _normalize(normalizeGradeLevel, gradeLevel),
      sectionName: _requireName(sectionName),
    );

    final existing = await repo.findExisting(wanted);
    if (existing != null) return (section: existing, created: false);

    final section = await repo.getOrCreate(wanted);
    await _refreshIfLoaded();
    return (section: section, created: true);
  }

  /// Changes year, grade and name. A section never moves to another school.
  Future<Section> update({
    required int id,
    required String schoolYear,
    required String gradeLevel,
    required String sectionName,
  }) async {
    _log('update(id: $id, year: "$schoolYear", grade: "$gradeLevel", name: "$sectionName")');
    final repo = _repo();
    final existing = await repo.getById(id);
    if (existing == null) throw ViewModelException('No section found with id $id.');
    _checkCanManage(existing.schoolId);

    try {
      final updated = await repo.update(Section(
        id: id,
        schoolId: existing.schoolId,
        schoolYear: _normalize(normalizeSchoolYear, schoolYear),
        gradeLevel: _normalize(normalizeGradeLevel, gradeLevel),
        sectionName: _requireName(sectionName),
        // Kept: the update writes every column, and the adviser is set elsewhere.
        adviserName: existing.adviserName,
        adviserUserId: existing.adviserUserId,
      ));
      await _refreshIfLoaded();
      return updated;
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        throw const ViewModelException('Another section with that year, grade and name already exists.');
      }
      rethrow;
    }
  }

  /// The section's adviser (ARAL Form 2; the adviser rule of the ARAL memo
  /// settings). [name] = the adviser's name as the school writes it; an
  /// account is optional. [userId] links the adviser's BASA account (a user
  /// of the section's school, checked here and by the server); left out, the
  /// current link is kept; [clearUser] removes it. A linked adviser without a
  /// typed name gets the account's full name. Online, admin/coordinator of
  /// the section's school (superadmin any); copied onto this device.
  Future<Section> setAdviser(int sectionId, {String? name, String? userId, bool clearUser = false}) async {
    _log('setAdviser($sectionId, name: $name, user: ${clearUser ? '-' : userId ?? 'kept'})');
    final repo = _repo();
    final existing = await repo.getById(sectionId);
    if (existing == null) throw ViewModelException('No section found with id $sectionId.');
    _checkCanManage(existing.schoolId);
    final link = clearUser ? null : (userId?.trim().isEmpty ?? true ? existing.adviserUserId : userId!.trim());
    String? accountName;
    if (link != null) {
      final users = _usersFor;
      final user = users == null ? null : await users(_auth.client!).getById(link);
      if (users != null && (user == null || user.schoolId != existing.schoolId)) {
        throw const ViewModelException("The adviser's BASA account must be a user of the section's school.");
      }
      accountName = user?.fullName;
    }
    final typed = name?.trim();
    final Section saved;
    try {
      saved = await repo.update(Section(
        id: existing.id,
        schoolId: existing.schoolId,
        schoolYear: existing.schoolYear,
        gradeLevel: existing.gradeLevel,
        sectionName: existing.sectionName,
        adviserName: typed == null || typed.isEmpty ? accountName : typed,
        adviserUserId: link,
      ));
    } on PostgrestException catch (e) {
      if (e.message.contains("adviser must be a user of the section's school")) {
        throw const ViewModelException("The adviser's BASA account must be a user of the section's school.");
      }
      rethrow;
    }
    lastMirrorWarning = null;
    final local = _local;
    if (local != null) {
      try {
        await local.upsertWithId(saved);
      } catch (e) {
        lastMirrorWarning = 'Saved online, but the copy on this device was not updated. Download the latest data.';
        _log('mirror failed: $e');
      }
    }
    await _refreshIfLoaded();
    return saved;
  }

  /// Refused by the database while anything still points at the section
  /// (enrollments, tutor assignments, CRLA assessments).
  Future<void> delete(int id) async {
    _log('delete($id)');
    final repo = _repo();
    final existing = await repo.getById(id);
    if (existing == null) throw ViewModelException('No section found with id $id.');
    _checkCanManage(existing.schoolId);

    try {
      await repo.delete(id);
    } on PostgrestException catch (e) {
      if (e.code == '23503') {
        throw const ViewModelException(
            'Section is still in use (enrollments, tutor assignments or assessments). Remove those first.');
      }
      rethrow;
    }
    await _refreshIfLoaded();
  }

  String _normalize(String Function(String) normalizer, String raw) {
    try {
      return normalizer(raw);
    } on FormatException catch (e) {
      throw ViewModelException(e.message);
    }
  }

  String _requireName(String raw) {
    final name = raw.trim();
    if (name.isEmpty) throw const ViewModelException('Section name is required.');
    return name;
  }

  Future<void> _refreshIfLoaded() async {
    if (items.isNotEmpty) await loadAll();
  }
}

// lib/viewmodels/phil_iri_content_viewmodel.dart
//
// Phil-IRI content and settings: material collections (+ rubric criteria),
// passages (+ comprehension questions) and the adjustable thresholds.
//
// Content is managed ONLINE, like sections: reads and writes go through the
// signed-in user's client (RLS applies), and every successful write is
// mirrored into the local database so PhilIriViewModel (offline) sees it
// without a new pull-cloud. A failed mirror never undoes the cloud write; it
// is reported in [lastMirrorWarning] (pull-cloud repairs the local copy).
//
// Who may write (checked here for a clear message; the cloud enforces it):
//  * region-wide collections, prescribed ones, promoting a school collection
//    and the region threshold row: superadmin only;
//  * a school's collections and its threshold override: the superadmin or
//    that school's admin/coordinator. Tutors only read.
import 'package:supabase/supabase.dart';

import '../core/console/logger.dart';
import '../core/models/phil_iri_collection.dart';
import '../core/models/phil_iri_passage.dart';
import '../core/models/phil_iri_question.dart';
import '../core/models/phil_iri_threshold_setting.dart';
import '../core/models/user_role.dart';
import '../core/repositories/phil_iri_collection_repository.dart';
import '../core/repositories/phil_iri_passage_repository.dart';
import '../core/repositories/phil_iri_threshold_repository.dart';
import '../core/services/phil_iri_rules.dart';
import 'auth_viewmodel.dart';
import 'viewmodel_exception.dart';

/// The Supabase repositories, built per signed-in client.
class PhilIriContentCloudRepos {
  final PhilIriCollectionRepository collections;
  final PhilIriPassageRepository passages;
  final PhilIriThresholdRepository thresholds;

  const PhilIriContentCloudRepos({
    required this.collections,
    required this.passages,
    required this.thresholds,
  });
}

/// The stored threshold rows that apply to one school and their merge.
class PhilIriThresholdLayers {
  final PhilIriThresholdSetting? region;
  final PhilIriThresholdSetting? school;
  final PhilIriThresholds effective;
  const PhilIriThresholdLayers(this.region, this.school, this.effective);
}

class PhilIriContentViewModel {
  final ScopedLogger _log;
  final AuthViewModel _auth;
  final PhilIriContentCloudRepos Function(SupabaseClient client) _cloudFor;
  final PhilIriCollectionRepository _localCollections;
  final PhilIriPassageRepository _localPassages;
  final PhilIriThresholdRepository _localThresholds;

  List<PhilIriCollection> collections = [];
  bool _collectionsActiveOnly = false;

  /// Set when the last write reached the cloud but its local copy failed.
  String? lastMirrorWarning;

  PhilIriContentViewModel({
    required AuthViewModel auth,
    required PhilIriContentCloudRepos Function(SupabaseClient client) cloudFactory,
    required PhilIriCollectionRepository localCollections,
    required PhilIriPassageRepository localPassages,
    required PhilIriThresholdRepository localThresholds,
    Logger? logger,
  })  : _auth = auth,
        _cloudFor = cloudFactory,
        _localCollections = localCollections,
        _localPassages = localPassages,
        _localThresholds = localThresholds,
        _log = ScopedLogger(logger, 'PhilIriContentViewModel');

  // ---- Access ----

  bool get _isSuperadmin =>
      _auth.currentUser?.role == UserRole.admin && _auth.currentUser?.schoolId == null;

  PhilIriContentCloudRepos _cloud() {
    final sessionError = _auth.requireOnlineSession();
    if (sessionError != null) throw ViewModelException(sessionError);
    return _cloudFor(_auth.client!);
  }

  /// For writes: also clears the previous mirror warning.
  PhilIriContentCloudRepos _writer() {
    final cloud = _cloud();
    final role = _auth.currentUser?.role;
    if (role != UserRole.admin && role != UserRole.coordinator) {
      throw const ViewModelException('Forbidden: admin or coordinator only.');
    }
    lastMirrorWarning = null;
    return cloud;
  }

  /// [schoolId] null = region-wide.
  void _checkCanManageSchool(int? schoolId, String what) {
    if (_isSuperadmin) return;
    if (schoolId == null) {
      throw ViewModelException('Forbidden: only the superadmin manages region-wide $what.');
    }
    if (_auth.currentUser?.schoolId != schoolId) {
      throw ViewModelException('Forbidden: you can only manage $what of your own school.');
    }
  }

  // ---- Collections ----

  /// Region-wide first, then by name. Tutors see what applies to their school.
  Future<void> loadCollections({bool activeOnly = false}) async {
    _log('loadCollections(activeOnly: $activeOnly)');
    _collectionsActiveOnly = activeOnly;
    collections = await _cloud().collections.getAll(activeOnly: activeOnly);
  }

  Future<PhilIriCollection> getCollection(int id) async {
    final c = await _cloud().collections.findById(id);
    if (c == null) throw ViewModelException('No collection with id $id.');
    return c;
  }

  /// [schoolId] null makes it region-wide (superadmin). Only region-wide
  /// collections can be prescribed (counted in DepEd reports).
  Future<PhilIriCollection> createCollection({
    required int? schoolId,
    required String name,
    String? description,
    bool isPrescribed = false,
    bool isGradeLeveled = true,
    bool hasComprehension = true,
    List<int>? readingOrder,
  }) async {
    _log('createCollection(schoolId: $schoolId, name: "$name", prescribed: $isPrescribed, '
        'graded: $isGradeLeveled, comprehension: $hasComprehension, order: $readingOrder)');
    final cloud = _writer();
    final wanted = _checkedCollection(PhilIriCollection(
      schoolId: schoolId,
      name: name,
      description: description,
      isPrescribed: isPrescribed,
      isGradeLeveled: isGradeLeveled,
      hasComprehension: hasComprehension,
      readingOrder: readingOrder,
    ));
    _checkCanManageSchool(schoolId, 'collections');

    final created = await _cloudWrite(() => cloud.collections.insert(wanted),
        duplicate: 'A collection named "${wanted.name}" already exists there.');
    await _mirror('Collection', () => _localCollections.upsertWithId(created));
    await _refreshCollectionsIfLoaded();
    return created;
  }

  /// Replaces name, description, flags and reading order. Moving a collection
  /// to another school or making it region-wide is superadmin-only (see
  /// [promoteCollection]).
  Future<PhilIriCollection> updateCollection(PhilIriCollection collection) async {
    _log('updateCollection(id: ${collection.id}, name: "${collection.name}")');
    if (collection.id == null) throw const ViewModelException('Collection has no id.');
    final cloud = _writer();
    final existing = await cloud.collections.findById(collection.id!);
    if (existing == null) throw ViewModelException('No collection with id ${collection.id}.');
    _checkCanManageSchool(existing.schoolId, 'collections');
    if (collection.schoolId != existing.schoolId && !_isSuperadmin) {
      throw const ViewModelException('Forbidden: only the superadmin moves a collection to another school or region-wide.');
    }
    final wanted = _checkedCollection(collection);

    final updated = await _cloudWrite(() => cloud.collections.update(wanted),
        duplicate: 'A collection named "${wanted.name}" already exists there.');
    await _mirror('Collection', () => _localCollections.upsertWithId(updated));
    await _refreshCollectionsIfLoaded();
    return updated;
  }

  /// Switches a collection on or off for assessments (its passages stay).
  Future<PhilIriCollection> setCollectionActive(int id, bool active) async {
    _log('setCollectionActive($id, $active)');
    final c = await getCollection(id);
    return updateCollection(_copyCollection(c, isActive: active));
  }

  /// Superadmin: makes a school-owned collection region-wide (visible to
  /// every school). It stays not prescribed until that is set separately.
  Future<PhilIriCollection> promoteCollection(int id) async {
    _log('promoteCollection($id)');
    if (!_isSuperadmin) {
      _cloud(); // a missing session is the clearer message
      throw const ViewModelException('Forbidden: superadmin only.');
    }
    final c = await getCollection(id);
    if (c.schoolId == null) throw const ViewModelException('This collection is already region-wide.');
    return updateCollection(_copyCollection(c, schoolId: null));
  }

  /// Refused while the collection still has passages; deactivate it instead.
  Future<void> deleteCollection(int id) async {
    _log('deleteCollection($id)');
    final cloud = _writer();
    final existing = await cloud.collections.findById(id);
    if (existing == null) throw ViewModelException('No collection with id $id.');
    _checkCanManageSchool(existing.schoolId, 'collections');

    final localCopy = await _localCollections.findById(id);
    final localCriteria = localCopy == null ? <PhilIriRubricCriterion>[] : await _localCollections.getCriteria(id);
    await _removeLocalFirst(() => _localCollections.removeMirrored(id));
    try {
      await _cloudWrite(() => cloud.collections.delete(id),
          inUse: 'This collection still has passages, or rubric scores use its criteria. '
              'Deactivate it instead, or remove those first.');
    } catch (_) {
      if (localCopy != null) {
        await _mirror('Collection', () async {
          await _localCollections.upsertWithId(localCopy);
          for (final k in localCriteria) {
            await _localCollections.upsertCriterionWithId(k);
          }
        });
      }
      rethrow;
    }
    await _refreshCollectionsIfLoaded();
  }

  PhilIriCollection _checkedCollection(PhilIriCollection c) {
    final name = c.name.trim();
    if (name.isEmpty) throw const ViewModelException('Collection name is required.');
    if (c.isPrescribed && c.schoolId != null) {
      throw const ViewModelException('Only region-wide collections can be prescribed.');
    }
    if (c.isPrescribed && !_isSuperadmin) {
      throw const ViewModelException('Forbidden: only the superadmin marks a collection as prescribed.');
    }
    final order = c.readingOrder;
    if (order != null && (order.isEmpty || order.any((n) => n < 1))) {
      throw const ViewModelException('A reading order lists selection numbers 1 and up (or leave it out).');
    }
    final description = c.description?.trim();
    return _copyCollection(c, name: name, description: (description?.isEmpty ?? true) ? null : description);
  }

  // ---- Rubric criteria ----

  /// Ordered by criterion_no.
  Future<List<PhilIriRubricCriterion>> criteria(int collectionId) async {
    _log('criteria($collectionId)');
    return _cloud().collections.getCriteria(collectionId);
  }

  /// [criterionNo] defaults to the next free number.
  Future<PhilIriRubricCriterion> addCriterion({
    required int collectionId,
    required String name,
    int scaleMin = 1,
    required int scaleMax,
    int? criterionNo,
  }) async {
    _log('addCriterion(collectionId: $collectionId, name: "$name", scale: $scaleMin..$scaleMax, no: $criterionNo)');
    final cloud = _writer();
    final collection = await cloud.collections.findById(collectionId);
    if (collection == null) throw ViewModelException('No collection with id $collectionId.');
    _checkCanManageSchool(collection.schoolId, 'collections');
    final existing = await cloud.collections.getCriteria(collectionId);
    final no = criterionNo ??
        (existing.isEmpty ? 1 : existing.map((k) => k.criterionNo).reduce((a, b) => a > b ? a : b) + 1);
    final wanted = _checkedCriterion(PhilIriRubricCriterion(
        collectionId: collectionId, criterionNo: no, name: name, scaleMin: scaleMin, scaleMax: scaleMax));
    _checkCriterionNameFree(existing, wanted);

    final created = await _cloudWrite(() => cloud.collections.insertCriterion(wanted),
        duplicate: 'This collection already has criterion number $no.');
    await _mirror('Rubric criterion', () => _localCollections.upsertCriterionWithId(created));
    return created;
  }

  /// Renames, renumbers or rescales a criterion. It stays in its collection.
  Future<PhilIriRubricCriterion> updateCriterion(PhilIriRubricCriterion criterion) async {
    _log('updateCriterion(id: ${criterion.id}, no: ${criterion.criterionNo}, name: "${criterion.name}")');
    final cloud = _writer();
    final collection = await _criterionCollection(cloud, criterion.collectionId, criterion.id);
    _checkCanManageSchool(collection.schoolId, 'collections');
    final wanted = _checkedCriterion(criterion);
    _checkCriterionNameFree(await cloud.collections.getCriteria(criterion.collectionId), wanted);

    final updated = await _cloudWrite(() => cloud.collections.updateCriterion(wanted),
        duplicate: 'This collection already has criterion number ${wanted.criterionNo}.');
    await _mirror('Rubric criterion', () => _localCollections.upsertCriterionWithId(updated));
    return updated;
  }

  Future<void> deleteCriterion(int collectionId, int criterionId) async {
    _log('deleteCriterion(collectionId: $collectionId, criterionId: $criterionId)');
    final cloud = _writer();
    final collection = await _criterionCollection(cloud, collectionId, criterionId);
    _checkCanManageSchool(collection.schoolId, 'collections');

    final localCopy = (await _localCollections.getCriteria(collectionId)).where((k) => k.id == criterionId).firstOrNull;
    await _removeLocalFirst(() => _localCollections.removeMirroredCriterion(criterionId));
    try {
      await _cloudWrite(() => cloud.collections.deleteCriterion(criterionId),
          inUse: 'Rubric scores use this criterion; it cannot be deleted.');
    } catch (_) {
      if (localCopy != null) await _mirror('Rubric criterion', () => _localCollections.upsertCriterionWithId(localCopy));
      rethrow;
    }
  }

  Future<PhilIriCollection> _criterionCollection(PhilIriContentCloudRepos cloud, int collectionId, int? criterionId) async {
    if (criterionId == null) throw const ViewModelException('Rubric criterion has no id.');
    final collection = await cloud.collections.findById(collectionId);
    if (collection == null) throw ViewModelException('No collection with id $collectionId.');
    final all = await cloud.collections.getCriteria(collectionId);
    if (!all.any((k) => k.id == criterionId)) {
      throw ViewModelException('Collection $collectionId has no rubric criterion with id $criterionId.');
    }
    return collection;
  }

  /// Names are unique within a collection (owner, 2026-10-14), ignoring case.
  /// Checked here only; the cloud has no matching constraint.
  void _checkCriterionNameFree(List<PhilIriRubricCriterion> existing, PhilIriRubricCriterion wanted) {
    final name = wanted.name.toLowerCase();
    final clash = existing.where((k) => k.id != wanted.id && k.name.trim().toLowerCase() == name).firstOrNull;
    if (clash != null) {
      throw ViewModelException('This collection already has a criterion named "${clash.name}" (#${clash.criterionNo}).');
    }
  }

  PhilIriRubricCriterion _checkedCriterion(PhilIriRubricCriterion k) {
    final name = k.name.trim();
    if (name.isEmpty) throw const ViewModelException('Criterion name is required.');
    if (k.criterionNo < 1) throw const ViewModelException('Criterion number starts at 1.');
    if (k.scaleMin >= k.scaleMax) {
      throw ViewModelException('The scale must go up (got ${k.scaleMin}..${k.scaleMax}).');
    }
    return PhilIriRubricCriterion(
        id: k.id, collectionId: k.collectionId, criterionNo: k.criterionNo, name: name,
        scaleMin: k.scaleMin, scaleMax: k.scaleMax);
  }

  // ---- Passages ----

  /// Ordered by level, set, selection number.
  Future<List<PhilIriPassage>> passages(int collectionId, {bool activeOnly = false}) async {
    _log('passages($collectionId, activeOnly: $activeOnly)');
    return _cloud().passages.getByCollection(collectionId, activeOnly: activeOnly);
  }

  Future<PhilIriPassage> getPassage(int id) async {
    final p = await _cloud().passages.findById(id);
    if (p == null) throw ViewModelException('No passage with id $id.');
    return p;
  }

  /// The word count must equal the number of words in the text: miscue taps
  /// use the text's words and the database bounds them by the word count.
  Future<PhilIriPassage> addPassage(PhilIriPassage passage) async {
    _log('addPassage(collectionId: ${passage.collectionId}, level: ${passage.level}, title: "${passage.title}")');
    final cloud = _writer();
    final collection = await cloud.collections.findById(passage.collectionId);
    if (collection == null) throw ViewModelException('No collection with id ${passage.collectionId}.');
    _checkCanManageSchool(collection.schoolId, 'passages');
    final wanted = _checkedPassage(passage, collection);

    final created = await _cloudWrite(() => cloud.passages.insert(wanted));
    await _mirror('Passage', () => _localPassages.upsertWithId(created));
    return created;
  }

  /// Once a passage has been read, its text, word count, level and
  /// collection are locked (the cloud refuses); title, motivation and set
  /// details can still change.
  Future<PhilIriPassage> updatePassage(PhilIriPassage passage) async {
    _log('updatePassage(id: ${passage.id}, level: ${passage.level}, title: "${passage.title}")');
    if (passage.id == null) throw const ViewModelException('Passage has no id.');
    final cloud = _writer();
    final existing = await cloud.passages.findById(passage.id!);
    if (existing == null) throw ViewModelException('No passage with id ${passage.id}.');
    final from = await cloud.collections.findById(existing.collectionId);
    _checkCanManageSchool(from?.schoolId, 'passages');
    final to = passage.collectionId == existing.collectionId ? from : await cloud.collections.findById(passage.collectionId);
    if (to == null) throw ViewModelException('No collection with id ${passage.collectionId}.');
    _checkCanManageSchool(to.schoolId, 'passages');
    final wanted = _checkedPassage(passage, to);

    final updated = await _cloudWrite(() => cloud.passages.update(wanted));
    await _mirror('Passage', () => _localPassages.upsertWithId(updated));
    return updated;
  }

  Future<PhilIriPassage> setPassageActive(int id, bool active) async {
    _log('setPassageActive($id, $active)');
    final p = await getPassage(id);
    return updatePassage(_copyPassage(p, isActive: active));
  }

  /// Refused once the passage has been read; deactivate it instead.
  Future<void> deletePassage(int id) async {
    _log('deletePassage($id)');
    final cloud = _writer();
    final existing = await cloud.passages.findById(id);
    if (existing == null) throw ViewModelException('No passage with id $id.');
    final collection = await cloud.collections.findById(existing.collectionId);
    _checkCanManageSchool(collection?.schoolId, 'passages');

    final localCopy = await _localPassages.findById(id);
    final localQuestions = localCopy == null ? <PhilIriQuestion>[] : await _localPassages.getQuestions(id);
    await _removeLocalFirst(() => _localPassages.removeMirrored(id));
    try {
      await _cloudWrite(() => cloud.passages.delete(id),
          inUse: 'This passage has been read; deactivate it instead.');
    } catch (_) {
      if (localCopy != null) {
        await _mirror('Passage', () async {
          await _localPassages.upsertWithId(localCopy);
          for (final q in localQuestions) {
            await _localPassages.upsertQuestionWithId(q);
          }
        });
      }
      rethrow;
    }
  }

  PhilIriPassage _checkedPassage(PhilIriPassage p, PhilIriCollection collection) {
    final title = p.title.trim();
    if (title.isEmpty) throw const ViewModelException('Passage title is required.');
    final body = p.body.trim();
    if (body.isEmpty) throw const ViewModelException('Passage text is required.');
    if (p.language != 'English') throw const ViewModelException('Only English passages are in scope.');
    if (collection.isGradeLeveled) {
      if (p.level == null) {
        throw ViewModelException('"${collection.name}" is grade-leveled: give the grade that reads this passage.');
      }
      if (p.level! < 1 || p.level! > philIriMaxGrade) {
        throw ViewModelException('Level must be a grade from 1 to $philIriMaxGrade.');
      }
    } else if (p.level != null) {
      throw ViewModelException('"${collection.name}" is not grade-leveled: its passages have no level.');
    }
    if (p.testType != null && !philIriTestTypes.contains(p.testType)) {
      throw const ViewModelException('Test type is "pre" (BOSY), "mosy" (MOSY), "post" (EOSY) or none.');
    }
    if (p.selectionNo != null && p.selectionNo! < 1) {
      throw const ViewModelException('Selection number starts at 1.');
    }
    final checked = _copyPassage(p, title: title, body: body,
        setCode: _blankToNull(p.setCode), motivation: _blankToNull(p.motivation));
    // Strict for now (owner, 2026-10-14), MAY CHANGE: printed sources count
    // words differently (dashes, numbers); a looser rule would need the
    // miscue bounds (word_count) and the tap tokens (words) to agree another way.
    if (!checked.wordCountMatches) {
      throw ViewModelException('The text has ${checked.words.length} words but the word count says '
          '${checked.wordCount}. Fix the text or the count (miscues are tapped on the text\'s words).');
    }
    return checked;
  }

  // ---- Questions ----

  /// Ordered by question_no.
  Future<List<PhilIriQuestion>> questions(int passageId) async {
    _log('questions($passageId)');
    return _cloud().passages.getQuestions(passageId);
  }

  /// [choices] in letter order; [answerKey] is a choice letter ('a', 'b', ...).
  /// [questionNo] defaults to the next free number.
  Future<PhilIriQuestion> addQuestion({
    required int passageId,
    required String prompt,
    required List<String> choices,
    required String answerKey,
    PhilIriQuestionType? questionType,
    int? questionNo,
  }) async {
    _log('addQuestion(passageId: $passageId, no: $questionNo, key: "$answerKey", choices: ${choices.length})');
    final cloud = _writer();
    await _questionPassage(cloud, passageId, null);
    final existing = await cloud.passages.getQuestions(passageId);
    final no = questionNo ??
        (existing.isEmpty ? 1 : existing.map((q) => q.questionNo).reduce((a, b) => a > b ? a : b) + 1);
    final wanted = _checkedQuestion(PhilIriQuestion(
        passageId: passageId, questionNo: no, questionType: questionType,
        prompt: prompt, choices: choices, answerKey: answerKey));

    final created = await _cloudWrite(() => cloud.passages.insertQuestion(wanted),
        duplicate: 'This passage already has question number $no.');
    await _mirror('Question', () => _localPassages.upsertQuestionWithId(created));
    return created;
  }

  /// The question stays on its passage.
  Future<PhilIriQuestion> updateQuestion(PhilIriQuestion question) async {
    _log('updateQuestion(id: ${question.id}, no: ${question.questionNo}, key: "${question.answerKey}")');
    final cloud = _writer();
    await _questionPassage(cloud, question.passageId, question.id ?? -1);
    final wanted = _checkedQuestion(question);

    final updated = await _cloudWrite(() => cloud.passages.updateQuestion(wanted),
        duplicate: 'This passage already has question number ${wanted.questionNo}.');
    await _mirror('Question', () => _localPassages.upsertQuestionWithId(updated));
    return updated;
  }

  Future<void> deleteQuestion(int passageId, int questionId) async {
    _log('deleteQuestion(passageId: $passageId, questionId: $questionId)');
    final cloud = _writer();
    await _questionPassage(cloud, passageId, questionId);

    final localCopy = (await _localPassages.getQuestions(passageId)).where((q) => q.id == questionId).firstOrNull;
    await _removeLocalFirst(() => _localPassages.removeMirroredQuestion(questionId));
    try {
      await _cloudWrite(() => cloud.passages.deleteQuestion(questionId),
          inUse: 'Answers were recorded for this question; it cannot be deleted.');
    } catch (_) {
      if (localCopy != null) await _mirror('Question', () => _localPassages.upsertQuestionWithId(localCopy));
      rethrow;
    }
  }

  /// Checks the passage exists, its collection takes questions and is the
  /// user's to manage; with [questionId], that the question is on it.
  Future<void> _questionPassage(PhilIriContentCloudRepos cloud, int passageId, int? questionId) async {
    final passage = await cloud.passages.findById(passageId);
    if (passage == null) throw ViewModelException('No passage with id $passageId.');
    final collection = await cloud.collections.findById(passage.collectionId);
    if (collection == null) throw ViewModelException('No collection with id ${passage.collectionId}.');
    _checkCanManageSchool(collection.schoolId, 'passages');
    if (!collection.hasComprehension) {
      throw ViewModelException('"${collection.name}" has no comprehension questions.');
    }
    if (questionId != null) {
      final all = await cloud.passages.getQuestions(passageId);
      if (!all.any((q) => q.id == questionId)) {
        throw ViewModelException('Passage $passageId has no question with id $questionId.');
      }
    }
  }

  PhilIriQuestion _checkedQuestion(PhilIriQuestion q) {
    final prompt = q.prompt.trim();
    if (prompt.isEmpty) throw const ViewModelException('Question text is required.');
    if (q.questionNo < 1) throw const ViewModelException('Question number starts at 1.');
    final choices = q.choices.map((c) => c.trim()).toList();
    if (choices.length < 2 || choices.any((c) => c.isEmpty)) {
      throw const ViewModelException('A question needs at least two non-empty choices.');
    }
    if (choices.length > 26) throw const ViewModelException('At most 26 choices (a to z).');
    final key = q.answerKey.trim().toLowerCase();
    final letters = [for (var i = 0; i < choices.length; i++) PhilIriQuestion.letterOf(i)];
    if (!letters.contains(key)) {
      throw ViewModelException('The answer key must be one of ${letters.join(', ')} (got "${q.answerKey}").');
    }
    return PhilIriQuestion(
        id: q.id, passageId: q.passageId, questionNo: q.questionNo, questionType: q.questionType,
        prompt: prompt, choices: choices, answerKey: key);
  }

  // ---- Thresholds ----

  /// The region row, [schoolId]'s override (none when null) and the values
  /// that apply: built-in defaults <- region <- school, key by key.
  Future<PhilIriThresholdLayers> thresholdLayers(int? schoolId) async {
    _log('thresholdLayers($schoolId)');
    final cloud = _cloud();
    final region = await cloud.thresholds.getRegion();
    final school = schoolId == null ? null : await cloud.thresholds.getForSchool(schoolId);
    return PhilIriThresholdLayers(
        region, school, PhilIriThresholds.fromMap({...?region?.settings, ...?school?.settings}));
  }

  /// Changes some threshold keys of the region row ([schoolId] null,
  /// superadmin) or a school's override (that school's admin/coordinator).
  /// Keys not in [changes] keep their stored value; a key set to null is
  /// removed from the row, so the layer below applies again. [replace]
  /// stores exactly [changes] instead. The values that would apply are
  /// validated before anything is saved.
  Future<PhilIriThresholdSetting> saveThresholds({
    required int? schoolId,
    required Map<String, Object?> changes,
    bool replace = false,
  }) async {
    _log('saveThresholds(schoolId: $schoolId, changes: $changes, replace: $replace)');
    final cloud = _writer();
    _checkCanManageSchool(schoolId, 'thresholds');
    _checkThresholdKeys(changes);

    final region = await cloud.thresholds.getRegion();
    final current = schoolId == null ? region : await cloud.thresholds.getForSchool(schoolId);
    final settings = <String, Object?>{if (!replace) ...?current?.settings, ...changes}
      ..removeWhere((_, v) => v == null);
    final effective = PhilIriThresholds.fromMap(
        schoolId == null ? settings : {...?region?.settings, ...settings});
    try {
      effective.validate();
    } on ArgumentError catch (e) {
      throw ViewModelException('${e.message}');
    }

    final saved = await _cloudWrite(() => cloud.thresholds.save(schoolId, settings));
    await _mirror('Thresholds', () => _localThresholds.upsertWithId(saved));
    return saved;
  }

  /// Removes a school's override so the region values apply again.
  Future<void> resetSchoolThresholds(int schoolId) async {
    _log('resetSchoolThresholds($schoolId)');
    final cloud = _writer();
    _checkCanManageSchool(schoolId, 'thresholds');
    if (await cloud.thresholds.getForSchool(schoolId) == null) {
      throw ViewModelException('School $schoolId has no threshold override.');
    }
    await _cloudWrite(() => cloud.thresholds.deleteForSchool(schoolId));
    await _mirror('Thresholds', () => _localThresholds.removeMirroredForSchool(schoolId));
  }

  /// fromMap silently ignores unknown keys and falls back on bad types, so a
  /// typo would save "nothing changed"; refuse it here instead.
  void _checkThresholdKeys(Map<String, Object?> changes) {
    final known = PhilIriThresholds.defaults.toMap();
    for (final e in changes.entries) {
      if (!known.containsKey(e.key)) {
        throw ViewModelException('Unknown threshold "${e.key}". Known: ${known.keys.join(', ')}.');
      }
      final v = e.value;
      if (v == null) continue;
      final ok = switch (known[e.key]) {
        bool _ => v is bool,
        List _ => v is List && v.every((x) => x is int),
        _ => v is int,
      };
      if (!ok) {
        final kind = switch (known[e.key]) { bool _ => 'true or false', List _ => 'a list of whole numbers', _ => 'a whole number' };
        throw ViewModelException('Threshold "${e.key}" must be $kind (got $v).');
      }
    }
  }

  // ---- Helpers ----

  /// Runs a cloud write and turns the database's refusals into messages.
  Future<T> _cloudWrite<T>(Future<T> Function() write, {String? duplicate, String? inUse}) async {
    try {
      return await write();
    } on PostgrestException catch (e) {
      if (e.code == '23505' && duplicate != null) throw ViewModelException(duplicate);
      if (e.code == '23503' && inUse != null) throw ViewModelException(inUse);
      if (e.code == '42501') throw const ViewModelException('Forbidden: the database refused this change.');
      if (e.code == 'P0001' && e.message.isNotEmpty) {
        // A trigger's own message ("this passage has already been read; ...").
        throw ViewModelException(e.message[0].toUpperCase() + e.message.substring(1));
      }
      rethrow;
    }
  }

  /// Drops the local copy before the cloud delete. The local repo refuses
  /// while assessments on this device still use the row: deleting it in the
  /// cloud would leave those unsyncable.
  Future<void> _removeLocalFirst(Future<void> Function() remove) async {
    try {
      await remove();
    } on StateError catch (e) {
      throw ViewModelException('${e.message}; sync them before deleting it.');
    }
  }

  Future<void> _mirror(String what, Future<void> Function() write) async {
    try {
      await write();
    } catch (e) {
      lastMirrorWarning = '$what saved online, but the local copy was not updated ($e). Run pull-cloud.';
      _log('WARNING: $lastMirrorWarning');
    }
  }

  Future<void> _refreshCollectionsIfLoaded() async {
    if (collections.isNotEmpty) await loadCollections(activeOnly: _collectionsActiveOnly);
  }

  static String? _blankToNull(String? s) {
    final t = s?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  static const _keep = Object();

  static PhilIriCollection _copyCollection(
    PhilIriCollection c, {
    Object? schoolId = _keep,
    String? name,
    Object? description = _keep,
    bool? isActive,
  }) =>
      PhilIriCollection(
        id: c.id,
        schoolId: identical(schoolId, _keep) ? c.schoolId : schoolId as int?,
        name: name ?? c.name,
        description: identical(description, _keep) ? c.description : description as String?,
        isPrescribed: c.isPrescribed,
        isGradeLeveled: c.isGradeLeveled,
        hasComprehension: c.hasComprehension,
        readingOrder: c.readingOrder,
        isActive: isActive ?? c.isActive,
        createdBy: c.createdBy,
      );

  static PhilIriPassage _copyPassage(
    PhilIriPassage p, {
    String? title,
    String? body,
    Object? setCode = _keep,
    Object? motivation = _keep,
    bool? isActive,
  }) =>
      PhilIriPassage(
        id: p.id,
        collectionId: p.collectionId,
        language: p.language,
        testType: p.testType,
        setCode: identical(setCode, _keep) ? p.setCode : setCode as String?,
        level: p.level,
        selectionNo: p.selectionNo,
        title: title ?? p.title,
        motivation: identical(motivation, _keep) ? p.motivation : motivation as String?,
        body: body ?? p.body,
        wordCount: p.wordCount,
        isActive: isActive ?? p.isActive,
        createdBy: p.createdBy,
      );
}

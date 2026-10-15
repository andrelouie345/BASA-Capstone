// lib/core/models/aral_checkin.dart
//
// ARAL-Reading check-in assessments. Source: the DepEd check-in tools in
// sample-files/ARAL/[FINAL] Check-Assessment Tools for KS 2-3 (one after
// session 16 and one after session 32, per key stage and track; none for KS1
// or Foundational). Owner decisions (2026-10-16):
//  * Per-item marks: a choice item stores the learner's letter and is scored
//    against the key by the database; an open item is marked by the tutor.
//  * Retakes allowed: attempt_no counts per learner and tool; the latest counts.
//  * Pass = score >= a percentage cut-off (aral_settings), judged when read.
//  * Record and report only: no effect on the IRIP, placement or exit.
import 'aral_enrollment.dart';

enum AralCheckinItemKind {
  choice,  // a letter A-E, scored against the key
  open;    // marked right/wrong by the tutor

  static AralCheckinItemKind fromString(String v) => AralCheckinItemKind.values.firstWhere(
        (k) => k.name == v,
        orElse: () => throw ArgumentError('Invalid AralCheckinItemKind value: $v'),
      );
}

/// One check-in tool (content; mirrored from the cloud).
class AralCheckinTool {
  final int id;
  final AralKeyStage keyStage;  // ks2 / ks3
  final AralTrack track;
  final int checkpoint;         // given after session 16 or 32
  final String language;        // 'filipino' / 'english'
  final String title;
  final bool isActive;

  const AralCheckinTool({
    required this.id,
    required this.keyStage,
    required this.track,
    required this.checkpoint,
    required this.language,
    required this.title,
    this.isActive = true,
  });

  /// e.g. "KS2 Basic, sessions 1-16".
  String get label => '${keyStage.label} ${track.label}, sessions ${checkpoint == 16 ? '1-16' : '17-32'}';

  Map<String, Object?> toMap() => {
        'id': id,
        'key_stage': keyStage.name,
        'track': track.name,
        'checkpoint': checkpoint,
        'language': language,
        'title': title,
        'is_active': isActive,
      };

  factory AralCheckinTool.fromMap(Map<String, Object?> m) => AralCheckinTool(
        id: m['id'] as int,
        keyStage: AralKeyStage.fromString(m['key_stage'] as String),
        track: AralTrack.fromString(m['track'] as String),
        checkpoint: m['checkpoint'] as int,
        language: m['language'] as String,
        title: m['title'] as String,
        isActive: m['is_active'] == null || m['is_active'] == true || m['is_active'] == 1,
      );
}

/// One item of a tool (content; mirrored from the cloud).
class AralCheckinItem {
  final int id;
  final int toolId;
  final int itemNo;          // 1..n over the whole tool
  final String? label;       // the printed number when the sheet restarts per part
  final String? section;     // the sheet's part; null = the tool has no parts
  final AralCheckinItemKind kind;
  final String? answerKey;   // choice: the letter; open: the expected answer (may be null)
  final String prompt;

  const AralCheckinItem({
    required this.id,
    required this.toolId,
    required this.itemNo,
    this.label,
    this.section,
    required this.kind,
    this.answerKey,
    required this.prompt,
  });

  /// The number as printed on the answer sheet.
  String get displayNo => label ?? '$itemNo';

  Map<String, Object?> toMap() => {
        'id': id,
        'tool_id': toolId,
        'item_no': itemNo,
        'label': label,
        'section': section,
        'kind': kind.name,
        'answer_key': answerKey,
        'prompt': prompt,
      };

  factory AralCheckinItem.fromMap(Map<String, Object?> m) => AralCheckinItem(
        id: m['id'] as int,
        toolId: m['tool_id'] as int,
        itemNo: m['item_no'] as int,
        label: m['label'] as String?,
        section: m['section'] as String?,
        kind: AralCheckinItemKind.fromString(m['kind'] as String),
        answerKey: m['answer_key'] as String?,
        prompt: m['prompt'] as String,
      );
}

/// One attempt of a learner at a tool.
class AralCheckin {
  final int? id;
  final int enrollmentId;   // aral_enrollments.id
  final int toolId;
  final int attemptNo;      // assigned by the database (0 = not yet)
  final String takenOn;     // YYYY-MM-DD
  final String? notes;
  final String? createdBy;
  final String? createdAt;
  final String? updatedAt;

  const AralCheckin({
    this.id,
    required this.enrollmentId,
    required this.toolId,
    this.attemptNo = 0,
    required this.takenOn,
    this.notes,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
  });

  /// attempt_no is assigned by the database and never sent on insert
  /// (0 = "assign the next number" locally).
  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'enrollment_id': enrollmentId,
        'tool_id': toolId,
        if (attemptNo > 0) 'attempt_no': attemptNo,
        'taken_on': takenOn,
        'notes': notes,
        if (createdBy != null) 'created_by': createdBy,
        if (createdAt != null) 'created_at': createdAt,
        if (updatedAt != null) 'updated_at': updatedAt,
      };

  factory AralCheckin.fromMap(Map<String, Object?> m) => AralCheckin(
        id: m['id'] as int?,
        enrollmentId: m['enrollment_id'] as int,
        toolId: m['tool_id'] as int,
        attemptNo: m['attempt_no'] as int? ?? 0,
        takenOn: m['taken_on'].toString().substring(0, 10),
        notes: m['notes'] as String?,
        createdBy: m['created_by'] as String?,
        createdAt: m['created_at']?.toString(),
        updatedAt: m['updated_at']?.toString(),
      );

  AralCheckin copyWith({String? takenOn, String? Function()? notes}) => AralCheckin(
        id: id,
        enrollmentId: enrollmentId,
        toolId: toolId,
        attemptNo: attemptNo,
        takenOn: takenOn ?? this.takenOn,
        notes: notes == null ? this.notes : notes(),
        createdBy: createdBy,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}

/// The learner's answer to one item of a check-in.
class AralCheckinAnswer {
  final int? id;
  final int checkinId;
  final int itemId;
  final String? response;   // choice: the letter (null = left blank); open: what the learner wrote
  final bool isCorrect;     // choice: computed by the database; open: the tutor's mark
  final String? createdAt;
  final String? updatedAt;

  const AralCheckinAnswer({
    this.id,
    required this.checkinId,
    required this.itemId,
    this.response,
    required this.isCorrect,
    this.createdAt,
    this.updatedAt,
  });

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'checkin_id': checkinId,
        'item_id': itemId,
        'response': response,
        'is_correct': isCorrect,
        if (createdAt != null) 'created_at': createdAt,
        if (updatedAt != null) 'updated_at': updatedAt,
      };

  factory AralCheckinAnswer.fromMap(Map<String, Object?> m) => AralCheckinAnswer(
        id: m['id'] as int?,
        checkinId: m['checkin_id'] as int,
        itemId: m['item_id'] as int,
        response: m['response'] as String?,
        isCorrect: m['is_correct'] == true || m['is_correct'] == 1,
        createdAt: m['created_at']?.toString(),
        updatedAt: m['updated_at']?.toString(),
      );
}

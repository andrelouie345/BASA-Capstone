// lib/core/repositories/aral_checkin_repository.dart
import '../models/aral_checkin.dart';
import '../models/aral_enrollment.dart';

/// Check-in tools and items (content, mirrored from the cloud) and learners'
/// check-ins with their answers. SQLite is the main write path for check-ins
/// (offline-first); the Supabase implementation has the same interface for
/// online use and the future sync.
abstract class AralCheckinRepository {
  /// The active tools, by key stage, track and checkpoint.
  Future<List<AralCheckinTool>> tools();

  Future<AralCheckinTool?> findTool(int id);

  /// The active tool for a placement and checkpoint (16 or 32), or null.
  Future<AralCheckinTool?> toolFor(AralKeyStage keyStage, AralTrack track, int checkpoint);

  /// The tool's items, by item_no.
  Future<List<AralCheckinItem>> items(int toolId);

  /// Every check-in of the learner, by tool then attempt.
  Future<List<AralCheckin>> checkins(int enrollmentId);

  Future<AralCheckin?> findCheckin(int id);

  /// The stored row comes back with its attempt_no.
  Future<AralCheckin> insertCheckin(AralCheckin checkin);

  /// Saves the changeable fields (taken_on, notes).
  Future<AralCheckin> updateCheckin(AralCheckin checkin);

  /// Deletes the check-in and its answers.
  Future<void> deleteCheckin(int id);

  /// The check-in's answers (any order).
  Future<List<AralCheckinAnswer>> answers(int checkinId);

  /// Inserts the answer, or updates the response and mark of the check-in's
  /// existing answer to that item. Choice items are scored by the database:
  /// the returned row carries the computed is_correct.
  Future<AralCheckinAnswer> saveAnswer(AralCheckinAnswer answer);

  /// Removes the check-in's answer to that item (no-op when there is none).
  Future<void> deleteAnswer(int checkinId, int itemId);

  /// Local-mirroring only: keep Supabase's ids (check-ins get origin 'cloud').
  /// Supabase impl throws UnimplementedError.
  Future<AralCheckinTool> upsertToolWithId(AralCheckinTool tool);
  Future<AralCheckinItem> upsertItemWithId(AralCheckinItem item);
  Future<AralCheckin> upsertCheckinWithId(AralCheckin checkin);
  Future<AralCheckinAnswer> upsertAnswerWithId(AralCheckinAnswer answer);
}

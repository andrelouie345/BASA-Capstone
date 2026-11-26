// Sending the demo builder's work through sync (demo-data plan Task 6): the
// uploader sends, the approver decides when the school doesn't auto-approve,
// and the uploader takes the result in, like a tablet would.
import 'dart:io';

import 'package:basa_capstone/core/models/sync_upload.dart';

import 'session.dart';

/// Groups [items] in order so each group's [bytes] add up to at most
/// [maxBytes]; an item over [maxBytes] on its own is refused.
List<List<T>> packages<T>(List<T> items, int Function(T) bytes, int maxBytes) {
  final out = <List<T>>[];
  var current = <T>[];
  var size = 0;
  for (final item in items) {
    final b = bytes(item);
    if (b > maxBytes) throw StateError('one item is $b bytes, over the upload limit of $maxBytes');
    if (current.isNotEmpty && size + b > maxBytes) {
      out.add(current);
      current = <T>[];
      size = 0;
    }
    current.add(item);
    size += b;
  }
  if (current.isNotEmpty) out.add(current);
  return out;
}

/// [uploader] sends their unsent work; when it isn't applied at once (the
/// school doesn't auto-approve), [approver] approves it, or rejects it with
/// [rejectReason], or (approve false, no reason) leaves it pending. The
/// uploader then takes the decision in. Returns the upload id.
Future<int> uploadAndDecide(DemoSession s, String uploader, String approver,
    {bool approve = true, String? rejectReason}) async {
  final dev = await s.as(uploader);
  final clock = Stopwatch()..start();
  final sent = await dev.shared.syncVm.upload();
  if (sent.outcome != null) {
    _timing('upload ${sent.uploadId}: ${sent.records} records sent and applied at once', clock);
  }
  if (sent.outcome == null) {
    if (!approve && rejectReason == null) return sent.uploadId;
    final review = (await s.as(approver)).admin;
    if (review == null) throw StateError('$approver is not an approver (tutor build)');
    if (rejectReason != null) {
      await review.syncReviewVm.reject(sent.uploadId, rejectReason);
    } else {
      final approval = Stopwatch()..start();
      final r = await review.syncReviewVm.approve(sent.uploadId);
      _timing('upload ${sent.uploadId}: ${sent.records} records approved', approval);
      if (r.status != 'applied') throw StateError('upload ${sent.uploadId} not applied: $r');
    }
  } else if (sent.outcome!.status != 'applied') {
    throw StateError('upload ${sent.uploadId} not applied: ${sent.outcome}');
  }
  final outcomes = await (await s.as(uploader)).shared.syncVm.refreshStatus();
  for (final SyncOutcome o in outcomes) {
    if (o.uploadId == sent.uploadId && approve && rejectReason == null && o.status != 'applied') {
      throw StateError('upload ${sent.uploadId}: $o');
    }
  }
  return sent.uploadId;
}

/// A run that stopped between sending and deciding leaves [uploader]'s upload
/// pending (its records read-only on the device, so a new upload doesn't hold
/// them): [approver] approves every pending upload of [uploader], and the
/// uploader takes the results in. Returns how many were approved.
Future<int> settlePending(DemoSession s, String uploader, String approver) async {
  final me = (await s.as(uploader)).ctx.authVm.currentUser!;
  final review = (await s.as(approver)).admin;
  if (review == null) throw StateError('$approver is not an approver (tutor build)');
  final mine = [
    for (final i in (await review.syncReviewVm.pending(schoolId: me.schoolId)).pending)
      if (i.upload.uploaderId == me.id) i.upload.id,
  ];
  for (final id in mine) {
    final approval = Stopwatch()..start();
    final r = await review.syncReviewVm.approve(id);
    _timing('pending upload $id approved', approval);
    if (r.status != 'applied') throw StateError('pending upload $id not applied: $r');
  }
  if (mine.isNotEmpty) await (await s.as(uploader)).shared.syncVm.refreshStatus();
  return mine.length;
}

/// Prints how long [clock] has run, so the approval times are on record
/// (sync_apply inserts row by row; the server allows it 60 s, 20261125030000).
void _timing(String what, Stopwatch clock) =>
    stdout.writeln('    $what in ${(clock.elapsedMilliseconds / 1000).toStringAsFixed(1)} s');

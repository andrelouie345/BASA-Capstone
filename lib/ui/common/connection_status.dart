// lib/ui/common/connection_status.dart
// Online or offline, and how much of this device's work waits in an upload
// (docs/handoff/screens/common.md, Online / offline and pending work).
// Records in a pending upload are read-only until an approver decides; the
// ViewModel refuses a write on one with its own message, so screens only
// need to say so here. Reads this device only (SyncViewModel.lockedCounts),
// so it works signed in offline too.
import 'package:flutter/material.dart';

import '../basa_scope.dart';

/// A small chip: "Online" / "Offline" and the number of locked records.
/// Give it a new [Key] to read the counts again (e.g. after an upload).
class ConnectionStatusChip extends StatefulWidget {
  /// Opens the sync screens (theirs to build); null = not tappable.
  final VoidCallback? onTap;
  const ConnectionStatusChip({super.key, this.onTap});

  @override
  State<ConnectionStatusChip> createState() => _ConnectionStatusChipState();
}

class _ConnectionStatusChipState extends State<ConnectionStatusChip> {
  /// Upload id → locked records; id 0 = an upload still being sent.
  Map<int, int>? _locked;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final vms = BasaScope.of(context);
    if (!vms.auth.isSignedIn) return;
    try {
      final locked = await vms.sync.lockedCounts();
      if (mounted) setState(() => _locked = locked);
    } catch (e) {
      // Status only: leave the count out, log why.
      debugPrint('ConnectionStatusChip: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = BasaScope.of(context).auth;
    if (!auth.isSignedIn) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    final offline = auth.isOffline;
    final pending = (_locked ?? const {}).values.fold(0, (a, b) => a + b);
    final bg = offline ? colors.secondaryContainer : colors.surfaceContainerHigh;
    final fg = offline ? colors.onSecondaryContainer : colors.onSurface;
    final dot = offline ? colors.secondary : colors.tertiary;

    return Tooltip(
      message: pendingTooltip(offline: offline, pending: pending),
      child: Material(
        color: bg,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text(
                  offline ? 'Offline' : 'Online',
                  style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 13),
                ),
                if (pending > 0) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.lock_clock, size: 16, color: fg),
                  const SizedBox(width: 4),
                  Text('$pending', style: TextStyle(color: fg, fontSize: 13)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String pendingTooltip({required bool offline, required int pending}) {
  final mode = offline
      ? 'Signed in offline: you work on this device\'s copy. Sending your work needs a connection.'
      : 'Signed in online.';
  if (pending == 0) return mode;
  final records = pending == 1 ? '1 record waits' : '$pending records wait';
  return '$mode\n$records for approval and can\'t be changed until it is decided.';
}

/// A full-width notice for screens that edit records: shown only when some
/// of this device's work waits in an upload.
class PendingWorkBanner extends StatefulWidget {
  const PendingWorkBanner({super.key});

  @override
  State<PendingWorkBanner> createState() => _PendingWorkBannerState();
}

class _PendingWorkBannerState extends State<PendingWorkBanner> {
  int _pending = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final vms = BasaScope.of(context);
      if (!vms.auth.isSignedIn) return;
      try {
        final locked = await vms.sync.lockedCounts();
        if (mounted) setState(() => _pending = locked.values.fold(0, (a, b) => a + b));
      } catch (e) {
        debugPrint('PendingWorkBanner: $e');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_pending == 0) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.lock_clock, color: colors.onSecondaryContainer, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${_pending == 1 ? '1 record waits' : '$_pending records wait'} for approval. '
                'They are read-only on this device until the upload is decided.',
                style: TextStyle(color: colors.onSecondaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

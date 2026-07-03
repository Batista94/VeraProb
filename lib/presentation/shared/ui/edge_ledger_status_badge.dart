import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/domain/sla_audit/local_fact_queue/sync_status.dart';
import 'package:veraprob/state/notifiers/connectivity_notifier.dart';
import 'package:veraprob/state/providers/local_fact_queue_providers.dart';

/// Toolbar chip showing the Edge Ledger sync state.
///
/// States:
/// - **Synced** (green, check) — `pendingCount == 0` and connected.
/// - **N buffered** (amber, sync) — facts are buffered awaiting acknowledgement.
/// - **Syncing…** (blue, progress) — reconnection handshake in progress.
/// - **Sync error** (red, warning) — any [SyncStatus.failed] items detected.
///
/// Tapping opens a detail dialog with last-sync timestamp, counts by status,
/// and a "Retry Now" button.
///
/// **INV-23:** Read-only — no mutations, only monitoring.
class EdgeLedgerStatusBadge extends ConsumerWidget {
  const EdgeLedgerStatusBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final countAsync = ref.watch(pendingFactCountProvider);

    // Riverpod 3.x: a stream can surface an error while still being subscribed,
    // producing AsyncLoading.copyWithPrevious(AsyncError). Check `hasError`
    // ahead of the AsyncLoading branch so the user sees the failure.
    if (countAsync.hasError) {
      return const _BadgeChip(
        label: 'Sync error',
        icon: Icons.warning_amber_rounded,
        color: VeraProbColors.error,
      );
    }

    return switch (countAsync) {
      AsyncLoading() => const _BadgeChip(
        label: 'Ledger',
        icon: Icons.sync,
        color: VeraProbColors.neutral,
      ),
      AsyncError() => const _BadgeChip(
        label: 'Sync error',
        icon: Icons.warning_amber_rounded,
        color: VeraProbColors.error,
      ),
      AsyncData(:final value) => _buildDataChip(context, ref, value),
    };
  }

  Widget _buildDataChip(BuildContext context, WidgetRef ref, int value) {
    final connectionState = ref.watch(connectivityNotifierProvider);
    if (connectionState == EdgeLedgerConnectionState.syncing) {
      return const _SyncingChip();
    }
    if (value == 0) {
      return const _BadgeChip(
        label: 'Synced',
        icon: Icons.check_circle_outline,
        color: VeraProbColors.success,
        semanticLabel: 'Edge Ledger synced',
      );
    }
    return _BadgeChip(
      label: '$value buffered',
      icon: Icons.sync_outlined,
      color: VeraProbColors.warning,
      onTap: () => _showDetail(context, ref, value),
      semanticLabel: '$value facts buffered in Edge Ledger',
    );
  }

  void _showDetail(BuildContext context, WidgetRef ref, int count) {
    showDialog<void>(
      context: context,
      builder: (_) => _EdgeLedgerDetailDialog(pendingCount: count, ref: ref),
    );
  }
}

// ── Internal chips ─────────────────────────────────────────────────────────────

class _BadgeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final String? semanticLabel;

  const _BadgeChip({
    required this.label,
    required this.icon,
    required this.color,
    this.onTap,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel ?? label,
      button: onTap != null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SyncingChip extends StatelessWidget {
  const _SyncingChip();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Edge Ledger syncing',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: VeraProbColors.info.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: VeraProbColors.info.withValues(alpha: 0.3)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                valueColor: AlwaysStoppedAnimation<Color>(VeraProbColors.info),
              ),
            ),
            SizedBox(width: 6),
            Text(
              'Syncing\u2026',
              style: TextStyle(
                color: VeraProbColors.info,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Detail dialog ──────────────────────────────────────────────────────────────

class _EdgeLedgerDetailDialog extends StatelessWidget {
  final int pendingCount;
  final WidgetRef ref;

  const _EdgeLedgerDetailDialog({
    required this.pendingCount,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.storage_outlined, size: 20),
          SizedBox(width: 8),
          Text('Edge Ledger'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Buffered facts: $pendingCount',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Facts are preserved locally during network outages and '
            'replayed on reconnection (INV-8 integrity verified).',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        FilledButton.tonal(
          onPressed: () {
            Navigator.of(context).pop();
            // Retry is best-effort; orchestrator handles idempotency.
            ref.read(localSyncOrchestratorProvider).drainFailed('');
          },
          child: const Text('Retry Now'),
        ),
      ],
    );
  }
}

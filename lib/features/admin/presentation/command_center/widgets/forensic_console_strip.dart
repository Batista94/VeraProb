import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/application/projections/forensic_ledger_view.dart';
import 'package:veraprob/state/providers/forensic_ledger_providers.dart';
import 'package:veraprob/core/theme/app_theme.dart';

/// Activity Console Strip (SOC/NOC Style)
///
/// A fixed horizontal strip at the bottom of the Command Center that consumes
/// the [forensicLedgerProjectionProvider] to display the Trust Backbone in real-time.
///
/// Features:
/// - Auto-scrolls ONLY when the operator is at the start (position 0)
/// - Displays narrative sentences from the Projection Layer
/// - Full manual scroll supported without interruption
class ForensicConsoleStrip extends ConsumerStatefulWidget {
  const ForensicConsoleStrip({super.key});

  @override
  ConsumerState<ForensicConsoleStrip> createState() =>
      _ForensicConsoleStripState();
}

class _ForensicConsoleStripState extends ConsumerState<ForensicConsoleStrip> {
  final ScrollController _scrollController = ScrollController();
  int _previousEntryCount = 0;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToNewestIfAtEdge(int currentCount) {
    if (currentCount > _previousEntryCount && _scrollController.hasClients) {
      // Only auto-scroll if the operator is already at the start (not
      // manually scrolling through older entries).
      final isAtStart =
          !_scrollController.hasClients ||
          !_scrollController.position.hasContentDimensions ||
          _scrollController.position.atEdge && _scrollController.offset <= 10.0;

      if (isAtStart) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              0.0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
            );
          }
        });
      }
    }
    _previousEntryCount = currentCount;
  }

  @override
  Widget build(BuildContext context) {
    final ledgerAsync = ref.watch(forensicLedgerProjectionProvider);

    return Container(
      height: 40,
      width: double.infinity,
      decoration: const BoxDecoration(
        color: VeraProbColors.surface,
        border: Border(top: BorderSide(color: VeraProbColors.border)),
      ),
      child: switch (ledgerAsync) {
        AsyncData(:final value) => _buildLedgerList(value),
        AsyncLoading() => const _LoadingConsole(),
        AsyncError() => const _ErrorConsole(),
      },
    );
  }

  Widget _buildLedgerList(List<ForensicLedgerEntry> value) {
    if (value.isEmpty) {
      return Center(
        child: Text(
          'FORENSIC LEDGER ACTIVE • WAITING FOR EVENTS',
          style: VeraProbTypography.mono(
            size: 11,
            color: VeraProbColors.textDisabled,
            letterSpacing: 1.2,
          ),
        ),
      );
    }

    final displayEntries = value.take(50).toList();
    _scrollToNewestIfAtEdge(displayEntries.length);

    return ListView.separated(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: displayEntries.length,
      separatorBuilder: (_, _) => const VerticalDivider(
        color: VeraProbColors.border,
        width: 16,
        thickness: 1,
        indent: 10,
        endIndent: 10,
      ),
      itemBuilder: (_, index) {
        final entry = displayEntries[index];
        return _ConsoleItem(
          time: _formatTime(entry.timestamp),
          narrative: entry.narrative,
          isApproved: entry.result == 'APPROVED',
        );
      },
    );
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')}';
  }
}

class _ConsoleItem extends StatelessWidget {
  final String time;
  final String narrative;
  final bool isApproved;

  const _ConsoleItem({
    required this.time,
    required this.narrative,
    required this.isApproved,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = isApproved
        ? VeraProbColors.success
        : VeraProbColors.error;
    final iconData = isApproved ? Icons.check_rounded : Icons.close_rounded;

    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '[$time]',
            style: VeraProbTypography.mono(
              size: 11,
              color: VeraProbColors.textSecondary,
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 350),
            child: Text(
              narrative,
              style: VeraProbTypography.mono(
                size: 11,
                color: VeraProbColors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          const SizedBox(width: 8),
          Icon(iconData, color: iconColor, size: 12),
        ],
      ),
    );
  }
}

class _LoadingConsole extends StatelessWidget {
  const _LoadingConsole();
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(
        width: 12,
        height: 12,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: VeraProbColors.primary,
        ),
      ),
    );
  }
}

class _ErrorConsole extends StatelessWidget {
  const _ErrorConsole();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Erro ao exibir registros forenses.',
          style: VeraProbTypography.mono(size: 11, color: VeraProbColors.error),
        ),
      ),
    );
  }
}

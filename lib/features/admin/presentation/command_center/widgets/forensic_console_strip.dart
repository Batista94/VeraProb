import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
        color: Color(0xFF1A1A1A),
        border: Border(top: BorderSide(color: Color(0xFF333333))),
      ),
      child: switch (ledgerAsync) {
        AsyncData(:final value) => () {
          if (value.isEmpty) {
            return const Center(
              child: Text(
                'FORENSIC LEDGER ACTIVE • WAITING FOR EVENTS',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                  fontFamily: 'monospace',
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
            separatorBuilder: (context, index) => const VerticalDivider(
              color: Colors.white12,
              width: 16,
              thickness: 1,
              indent: 10,
              endIndent: 10,
            ),
            itemBuilder: (context, index) {
              final entry = displayEntries[index];
              return _ConsoleItem(
                time: _formatTime(entry.timestamp),
                narrative: entry.narrative,
                isApproved: entry.result == 'APPROVED',
              );
            },
          );
        }(),
        AsyncLoading() => const _LoadingConsole(),
        AsyncError(:final error) => _ErrorConsole(err: error.toString()),
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
        ? const Color(0xFF4CAF50)
        : const Color(0xFFF44336);
    final icon = isApproved ? '✔' : '❌';

    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '[$time]',
            style: const TextStyle(
              color: Colors.white54,
              fontFamily: 'monospace',
              fontSize: 11,
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 350),
            child: Text(
              narrative,
              style: const TextStyle(
                color: Colors.white70,
                fontFamily: 'monospace',
                fontSize: 11,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          const SizedBox(width: 8),
          Text(icon, style: TextStyle(color: iconColor, fontSize: 10)),
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
  final String err;
  const _ErrorConsole({required this.err});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'LEDGER ERROR: $err',
          style: const TextStyle(
            color: Color(0xFFF44336),
            fontFamily: 'monospace',
            fontSize: 11,
          ),
        ),
      ),
    );
  }
}

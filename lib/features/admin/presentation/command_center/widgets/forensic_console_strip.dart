import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:busflow/application/projections/providers/forensic_ledger_provider.dart';
import 'package:busflow/core/theme/app_theme.dart';

/// Activity Console Strip (SOC/NOC Style)
///
/// A fixed horizontal strip at the bottom of the Command Center that consumes
/// the [forensicLedgerProjectionProvider] to display the Trust Backbone in real-time.
class ForensicConsoleStrip extends ConsumerWidget {
  const ForensicConsoleStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Escuta a stream contínua de decisões forenses projetadas em memória
    final ledgerAsync = ref.watch(forensicLedgerProjectionProvider);

    return Container(
      height: 40,
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A), // Strict dark background
        border: Border(top: BorderSide(color: Color(0xFF333333))),
      ),
      child: ledgerAsync.when(
        data: (entries) {
          if (entries.isEmpty) {
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

          // Render horizontally, limiting to 50 items so memory doesn't leak indefinitely
          final displayEntries = entries.take(50).toList();

          return ListView.separated(
            scrollDirection: Axis.horizontal,
            reverse:
                false, // We assume projected entries are newest-first. We want them flowing left to right.
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
                actor: entry.actorId,
                action: entry.actionType,
                isApproved: entry.result == 'APPROVED',
              );
            },
          );
        },
        loading: () => const _LoadingConsole(),
        error: (err, stack) => _ErrorConsole(err: err.toString()),
      ),
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
  final String actor;
  final String action;
  final bool isApproved;

  const _ConsoleItem({
    required this.time,
    required this.actor,
    required this.action,
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
          Text(
            actor,
            style: const TextStyle(
              color: BusFlowColors.primary,
              fontFamily: 'monospace',
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            '•',
            style: TextStyle(color: Colors.white24, fontSize: 11),
          ),
          const SizedBox(width: 6),
          Text(
            action,
            style: const TextStyle(
              color: Colors.white70,
              fontFamily: 'monospace',
              fontSize: 11,
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
          color: BusFlowColors.primary,
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

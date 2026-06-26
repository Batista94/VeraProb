import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:veraprob/application/ad_hoc_cost/shadow_execution_summary.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/shadow_providers.dart';

// ── Widget ────────────────────────────────────────────────────────────────────

/// Orphan triage tab — shows unlinked shadow executions with Smart Link.
class OrphanTriageTab extends ConsumerWidget {
  const OrphanTriageTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shadowsAsync = ref.watch(unlinkedShadowsProvider);

    return switch (shadowsAsync) {
      AsyncLoading() => const Center(child: CircularProgressIndicator()),
      AsyncError() => const Center(
        child: Text(
          'Não foi possível carregar os registros órfãos.',
          style: TextStyle(color: VeraProbColors.error),
        ),
      ),
      AsyncData(:final value) => _buildOrphanList(value),
    };
  }

  Widget _buildOrphanList(List<ShadowExecutionSummary> value) {
    if (value.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.check_circle_outline,
              size: 48,
              color: VeraProbColors.success,
            ),
            const SizedBox(height: 12),
            Text(
              '✅ Nenhum órfão pendente',
              style: VeraProbTypography.dataValue.copyWith(
                color: VeraProbColors.success,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: value.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, i) => _ShadowCard(shadow: value[i]),
    );
  }
}

class _ShadowCard extends ConsumerWidget {
  final ShadowExecutionSummary shadow;
  const _ShadowCard({required this.shadow});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final candidatesAsync = ref.watch(smartLinkCandidatesProvider(shadow));
    final ts = DateTime.fromMillisecondsSinceEpoch(
      shadow.messageTs * 1000,
      isUtc: true,
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: VeraProbColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: VeraProbColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.link_off,
                size: 16,
                color: VeraProbColors.warning,
              ),
              const SizedBox(width: 8),
              Text(
                'Operador: ${shadow.operatorId.substring(0, 8)}…',
                style: const TextStyle(
                  color: VeraProbColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              Text(
                DateFormat('dd/MM HH:mm:ss').format(ts),
                style: const TextStyle(
                  color: VeraProbColors.textSecondary,
                  fontFamily: 'monospace',
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Canal: ${shadow.originChannel} · Msg #${shadow.telegramMessageId}',
            style: const TextStyle(
              color: VeraProbColors.textSecondary,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 12),
          // Smart Link candidates
          switch (candidatesAsync) {
            AsyncLoading() => const SizedBox(
              height: 20,
              child: Center(child: LinearProgressIndicator()),
            ),
            AsyncError() => const Text(
              'Erro ao buscar candidatos',
              style: TextStyle(color: VeraProbColors.error, fontSize: 11),
            ),
            AsyncData(:final value) => _buildCandidateList(value),
          },
        ],
      ),
    );
  }

  Widget _buildCandidateList(List<Map<String, dynamic>> value) {
    if (value.isEmpty) {
      return const Text(
        'Nenhuma viagem compatível (±30min)',
        style: TextStyle(
          color: VeraProbColors.textSecondary,
          fontSize: 11,
          fontStyle: FontStyle.italic,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'SMART LINK — Viagens compatíveis:',
          style: TextStyle(
            color: VeraProbColors.primary,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        ...value.map(
          (c) => _CandidateRow(
            setId: c['set_id'] as String,
            windowStart: c['window_start_utc'] as String,
            status: c['status'] as String? ?? '',
            shadowId: shadow.id,
            orgId: shadow.organizationId,
          ),
        ),
      ],
    );
  }
}

class _CandidateRow extends ConsumerWidget {
  final String setId;
  final String windowStart;
  final String status;
  final String shadowId;
  final String orgId;

  const _CandidateRow({
    required this.setId,
    required this.windowStart,
    required this.status,
    required this.shadowId,
    required this.orgId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final startDt = DateTime.tryParse(windowStart);
    final startLabel = startDt != null
        ? DateFormat('dd/MM HH:mm').format(startDt)
        : windowStart;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$setId · $startLabel · $status',
              style: const TextStyle(
                color: VeraProbColors.textPrimary,
                fontFamily: 'monospace',
                fontSize: 11,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 28,
            child: ElevatedButton(
              onPressed: () => _reconcile(ref),
              style: ElevatedButton.styleFrom(
                backgroundColor: VeraProbColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                textStyle: const TextStyle(fontSize: 11),
              ),
              child: const Text('Vincular'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _reconcile(WidgetRef ref) async {
    final repo = ref.read(shadowRepoProvider);
    final userId = ref.read(currentOperatorIdProvider) ?? 'occ-operator';
    await repo.reconcile(
      id: shadowId,
      organizationId: orgId,
      reconciledExecutionId: setId,
      reconciledByUserId: userId,
      atUtc: DateTime.now().toUtc(),
    );
    ref.invalidate(unlinkedShadowsProvider);
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:veraprob/application/admin/governance_audit_query_service.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/state/providers/admin_providers.dart';

enum _PeriodPreset { last24h, last7d, last30d, all }

/// PT-BR label + semantic tint for a governance/audit event type. Falls back
/// to the raw event type for anything outside the known set — never hides an
/// event just because the UI doesn't have a label for it yet (Availability).
({String label, IconData icon, Color color}) _presentationFor(
  String eventType,
) => switch (eventType) {
  'ROLE_ASSIGNED' => (
    label: 'Perfil atribuído',
    icon: Icons.assignment_ind_outlined,
    color: VeraProbColors.success,
  ),
  'ROLE_REVOKED' => (
    label: 'Perfil revogado',
    icon: Icons.remove_circle_outline,
    color: VeraProbColors.warning,
  ),
  'ROLE_CREATED' => (
    label: 'Perfil criado',
    icon: Icons.add_moderator_outlined,
    color: VeraProbColors.primary,
  ),
  'ROLE_PERMISSIONS_CHANGED' => (
    label: 'Permissões do perfil alteradas',
    icon: Icons.tune,
    color: VeraProbColors.primary,
  ),
  'ROLE_CHANGE_REQUESTED' => (
    label: 'Alteração de perfil solicitada',
    icon: Icons.hourglass_empty_outlined,
    color: VeraProbColors.warning,
  ),
  'ROLE_CHANGE_APPROVED' => (
    label: 'Alteração de perfil aprovada',
    icon: Icons.check_circle_outline,
    color: VeraProbColors.success,
  ),
  'ROLE_CHANGE_REJECTED' => (
    label: 'Alteração de perfil rejeitada',
    icon: Icons.cancel_outlined,
    color: VeraProbColors.error,
  ),
  'MEMBER_DEACTIVATED' => (
    label: 'Membro inativado',
    icon: Icons.person_off_outlined,
    color: VeraProbColors.warning,
  ),
  'MEMBER_REACTIVATED' => (
    label: 'Membro reativado',
    icon: Icons.person_outline,
    color: VeraProbColors.success,
  ),
  'MEMBER_REMOVED' => (
    label: 'Membro removido',
    icon: Icons.person_remove_outlined,
    color: VeraProbColors.error,
  ),
  'MEMBER_ROLE_CHANGED' => (
    label: 'Perfil legado do membro alterado',
    icon: Icons.swap_horiz,
    color: VeraProbColors.primary,
  ),
  'MEMBER_INVITED' => (
    label: 'Convite enviado',
    icon: Icons.mail_outline,
    color: VeraProbColors.primary,
  ),
  'INVITATION_ACCEPTED' => (
    label: 'Convite aceito',
    icon: Icons.how_to_reg_outlined,
    color: VeraProbColors.success,
  ),
  'INVITATION_REVOKED' => (
    label: 'Convite revogado',
    icon: Icons.cancel_outlined,
    color: VeraProbColors.error,
  ),
  _ => (
    label: eventType,
    icon: Icons.info_outline,
    color: VeraProbColors.textSecondary,
  ),
};

/// "Histórico" tab in the Settings Hub — governance audit trail for tenant
/// member/role-management actions, visible only with `roles:read` (mirrors
/// the Acessos tab gate). Reads exclusively through the org-scoped
/// `get_tenant_governance_log` RPC (INV-1, INV-2, INV-22).
class GovernanceAuditScreen extends ConsumerStatefulWidget {
  const GovernanceAuditScreen({super.key});

  @override
  ConsumerState<GovernanceAuditScreen> createState() =>
      _GovernanceAuditScreenState();
}

class _GovernanceAuditScreenState extends ConsumerState<GovernanceAuditScreen> {
  GovernanceEventCategory? _category;
  _PeriodPreset _period = _PeriodPreset.last30d;
  String _emailFilter = '';

  DateTime? get _periodCutoffUtc {
    final now = DateTime.now().toUtc();
    return switch (_period) {
      _PeriodPreset.last24h => now.subtract(const Duration(hours: 24)),
      _PeriodPreset.last7d => now.subtract(const Duration(days: 7)),
      _PeriodPreset.last30d => now.subtract(const Duration(days: 30)),
      _PeriodPreset.all => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final entriesAsync = ref.watch(governanceAuditLogProvider(_category));

    return Padding(
      padding: const EdgeInsets.all(VeraProbSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.history_outlined,
                size: 24,
                color: VeraProbColors.primary,
              ),
              const SizedBox(width: 12),
              Text(
                'Histórico de Governança',
                style: VeraProbTypography.sectionTitle,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Trilha de auditoria de perfis, membros e convites da sua organização.',
            style: VeraProbTypography.bodyMedium.copyWith(
              color: VeraProbColors.textSecondary,
            ),
          ),
          const SizedBox(height: VeraProbSpacing.md),
          _buildFilterBar(),
          const SizedBox(height: VeraProbSpacing.sm),
          Expanded(child: _buildBody(entriesAsync)),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search, size: 18),
              hintText: 'Filtrar por e-mail (ator ou alvo)',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _emailFilter = v.trim()),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 180,
          child: DropdownButtonFormField<GovernanceEventCategory?>(
            initialValue: _category,
            isExpanded: true,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Categoria',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: null, child: Text('Todas')),
              DropdownMenuItem(
                value: GovernanceEventCategory.roles,
                child: Text('Perfis'),
              ),
              DropdownMenuItem(
                value: GovernanceEventCategory.members,
                child: Text('Membros'),
              ),
              DropdownMenuItem(
                value: GovernanceEventCategory.invites,
                child: Text('Convites'),
              ),
            ],
            onChanged: (v) => setState(() => _category = v),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 170,
          child: DropdownButtonFormField<_PeriodPreset>(
            initialValue: _period,
            isExpanded: true,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Período',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(
                value: _PeriodPreset.last24h,
                child: Text('Últimas 24h'),
              ),
              DropdownMenuItem(
                value: _PeriodPreset.last7d,
                child: Text('Últimos 7 dias'),
              ),
              DropdownMenuItem(
                value: _PeriodPreset.last30d,
                child: Text('Últimos 30 dias'),
              ),
              DropdownMenuItem(value: _PeriodPreset.all, child: Text('Tudo')),
            ],
            onChanged: (v) => setState(() => _period = v ?? _period),
          ),
        ),
      ],
    );
  }

  Widget _buildBody(AsyncValue<List<GovernanceAuditEntry>> entriesAsync) {
    return switch (entriesAsync) {
      AsyncData(:final value) => _buildList(_applyClientFilters(value)),
      AsyncError() => const Center(
        child: Text(
          'Não foi possível carregar o histórico de governança. Tente novamente.',
          style: TextStyle(color: VeraProbColors.error),
        ),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }

  List<GovernanceAuditEntry> _applyClientFilters(
    List<GovernanceAuditEntry> entries,
  ) {
    final cutoff = _periodCutoffUtc;
    return entries.where((e) {
      if (cutoff != null && e.occurredAtUtc.isBefore(cutoff)) return false;
      if (_emailFilter.isEmpty) return true;
      final needle = _emailFilter.toLowerCase();
      final actor = e.actorEmail?.toLowerCase() ?? '';
      final target = e.targetEmail?.toLowerCase() ?? '';
      return actor.contains(needle) || target.contains(needle);
    }).toList();
  }

  Widget _buildList(List<GovernanceAuditEntry> entries) {
    if (entries.isEmpty) {
      return Center(
        child: Text(
          'Nenhum evento de governança encontrado para os filtros selecionados.',
          style: VeraProbTypography.bodyMedium.copyWith(
            color: VeraProbColors.textSecondary,
          ),
        ),
      );
    }
    return ListView.separated(
      itemCount: entries.length,
      separatorBuilder: (_, _) => const Divider(color: VeraProbColors.border),
      itemBuilder: (context, i) => _GovernanceEntryTile(
        entry: entries[i],
        onTap: () => _showDetail(context, entries[i]),
      ),
    );
  }

  Future<void> _showDetail(
    BuildContext context,
    GovernanceAuditEntry entry,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _GovernanceDetailDialog(entry: entry),
    );
  }
}

class _GovernanceEntryTile extends StatelessWidget {
  const _GovernanceEntryTile({required this.entry, required this.onTap});

  final GovernanceAuditEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final presentation = _presentationFor(entry.eventType);
    final when = DateFormat(
      'dd/MM/yyyy HH:mm',
    ).format(entry.occurredAtUtc.toLocal());
    final actor = entry.actorEmail ?? 'Sistema';
    final target = entry.targetEmail;

    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: presentation.color.withValues(alpha: 0.12),
        child: Icon(presentation.icon, size: 18, color: presentation.color),
      ),
      title: Text(presentation.label, style: VeraProbTypography.kpiLabel),
      subtitle: Text(
        target == null ? '$actor · $when' : '$actor → $target · $when',
        style: VeraProbTypography.caption,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(
        Icons.chevron_right,
        size: 18,
        color: VeraProbColors.textSecondary,
      ),
    );
  }
}

class _GovernanceDetailDialog extends StatelessWidget {
  const _GovernanceDetailDialog({required this.entry});

  final GovernanceAuditEntry entry;

  @override
  Widget build(BuildContext context) {
    final presentation = _presentationFor(entry.eventType);
    final when = DateFormat(
      'dd/MM/yyyy HH:mm:ss',
    ).format(entry.occurredAtUtc.toLocal());

    return AlertDialog(
      title: Text(presentation.label),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DetailRow(label: 'Quando', value: when),
            _DetailRow(label: 'Ator', value: entry.actorEmail ?? 'Sistema'),
            if (entry.targetEmail != null)
              _DetailRow(label: 'Alvo', value: entry.targetEmail!),
            if (entry.reason != null && entry.reason!.isNotEmpty)
              _DetailRow(label: 'Motivo', value: entry.reason!),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fechar'),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: VeraProbTypography.caption.copyWith(
              color: VeraProbColors.textSecondary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(value, style: VeraProbTypography.bodyMedium),
        ],
      ),
    );
  }
}

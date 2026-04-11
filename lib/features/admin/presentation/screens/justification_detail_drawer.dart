import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/justification_providers.dart';
import 'widgets/justification_status_badge.dart';

/// Side drawer showing justification details with approve/reject actions.
///
/// Approve / Reject buttons are visible only for admin/operator
/// ([UserPermission.canReviewJustifications]) when status == pending.
/// INV-22: actor ID + email carried in ledger entries via [JustificationActionNotifier].
/// INV-24: opened via [showGeneralDialog] as an overlay.
class JustificationDetailDrawer extends ConsumerStatefulWidget {
  final Map<String, dynamic> row;

  const JustificationDetailDrawer({super.key, required this.row});

  @override
  ConsumerState<JustificationDetailDrawer> createState() =>
      _JustificationDetailDrawerState();
}

class _JustificationDetailDrawerState
    extends ConsumerState<JustificationDetailDrawer> {
  final _rejectNotesController = TextEditingController();
  bool _showRejectForm = false;

  @override
  void dispose() {
    _rejectNotesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.row['id'] as String;
    final status = JustificationStatus.fromDb(widget.row['status'] as String);
    final role = ref.watch(currentUserRoleProvider);
    final canReview = RbacService().can(
      role,
      UserPermission.canReviewJustifications,
    );
    final actionState = ref.watch(justificationActionStateProvider(id));

    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        width: 420,
        height: double.infinity,
        decoration: const BoxDecoration(
          color: VeraProbColors.surface,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(16),
            bottomLeft: Radius.circular(16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DrawerHeader(onClose: () => Navigator.pop(context)),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [JustificationStatusBadge(status: status)]),
                    const SizedBox(height: 24),
                    _InfoField(
                      label: 'Contrato',
                      value: widget.row['contract_id'] as String? ?? '-',
                    ),
                    _InfoField(
                      label: 'SET ID',
                      value: widget.row['set_id'] as String? ?? '-',
                    ),
                    _InfoField(
                      label: 'Categoria',
                      value: _categoryLabel(
                        (widget.row['category'] as String? ?? '').toLowerCase(),
                      ),
                    ),
                    const Divider(height: 40),
                    Text('DESCRIÇÃO', style: VeraProbTypography.caption),
                    const SizedBox(height: 8),
                    Text(
                      widget.row['description'] as String? ?? '-',
                      style: VeraProbTypography.bodyMedium,
                    ),
                    const Divider(height: 40),
                    _InfoField(
                      label: 'Enviado em',
                      value: _formatDate(
                        widget.row['created_at_utc'] as String?,
                      ),
                    ),
                    if (widget.row['reviewed_by_user_id'] != null) ...[
                      _InfoField(
                        label: 'Revisado por',
                        value: widget.row['reviewed_by_user_id'] as String,
                      ),
                      _InfoField(
                        label: 'Revisado em',
                        value: _formatDate(
                          widget.row['reviewed_at_utc'] as String?,
                        ),
                      ),
                    ],
                    if (canReview && status.isPending) ...[
                      const SizedBox(height: 24),
                      if (actionState.hasError)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            'Erro: ${actionState.error}',
                            style: const TextStyle(
                              color: VeraProbColors.error,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      if (_showRejectForm) ...[
                        Text(
                          'MOTIVO DA REJEIÇÃO',
                          style: VeraProbTypography.caption,
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _rejectNotesController,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            hintText: 'Mínimo 10 caracteres...',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () =>
                                    setState(() => _showRejectForm = false),
                                child: const Text('Cancelar'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: actionState.isLoading
                                    ? null
                                    : () => _reject(id),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: VeraProbColors.error,
                                  foregroundColor: Colors.white,
                                ),
                                child: actionState.isLoading
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text('Confirmar Rejeição'),
                              ),
                            ),
                          ],
                        ),
                      ] else
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: actionState.isLoading
                                    ? null
                                    : () => _approve(id),
                                icon: actionState.isLoading
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.check, size: 16),
                                label: const Text('Aprovar'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: VeraProbColors.success,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: actionState.isLoading
                                    ? null
                                    : () => setState(
                                        () => _showRejectForm = true,
                                      ),
                                icon: const Icon(Icons.close, size: 16),
                                label: const Text('Rejeitar'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: VeraProbColors.error,
                                  side: const BorderSide(
                                    color: VeraProbColors.error,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _approve(String id) async {
    final orgId = ref.read(currentOrganizationIdProvider);
    final userId = ref.read(currentOperatorIdProvider);
    final role = ref.read(currentUserRoleProvider);
    final session = ref.read(authStateProvider).valueOrNull?.session;
    final email = session?.user.email ?? '';
    final sessionId = ref.read(currentSessionIdProvider) ?? '';

    if (orgId == null || userId == null) return;

    await ref
        .read(justificationActionStateProvider(id).notifier)
        .approve(
          justificationId: id,
          organizationId: orgId,
          planVersion: 0,
          callerRole: role,
          callerUserId: userId,
          callerEmail: email,
          sessionId: sessionId,
        );

    if (!mounted) return;

    final state = ref.read(justificationActionStateProvider(id));
    if (!state.hasError) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Justificativa aprovada com sucesso.')),
      );
    }
  }

  Future<void> _reject(String id) async {
    final notes = _rejectNotesController.text.trim();
    if (notes.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Motivo deve ter pelo menos 10 caracteres.'),
          backgroundColor: VeraProbColors.error,
        ),
      );
      return;
    }

    final orgId = ref.read(currentOrganizationIdProvider);
    final userId = ref.read(currentOperatorIdProvider);
    final role = ref.read(currentUserRoleProvider);
    final session = ref.read(authStateProvider).valueOrNull?.session;
    final email = session?.user.email ?? '';
    final sessionId = ref.read(currentSessionIdProvider) ?? '';

    if (orgId == null || userId == null) return;

    await ref
        .read(justificationActionStateProvider(id).notifier)
        .reject(
          justificationId: id,
          organizationId: orgId,
          planVersion: 0,
          callerRole: role,
          callerUserId: userId,
          callerEmail: email,
          rejectionNotes: notes,
          sessionId: sessionId,
        );

    if (!mounted) return;

    final state = ref.read(justificationActionStateProvider(id));
    if (!state.hasError) {
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Justificativa rejeitada.')));
    }
  }

  String _categoryLabel(String raw) {
    return switch (raw) {
      'mechanical' => 'Mecânico',
      'force_majeure' => 'Força Maior',
      'traffic' => 'Trânsito',
      'route_deviation' => 'Desvio de Rota',
      'communication' => 'Comunicação',
      _ => 'Outro',
    };
  }

  String _formatDate(String? raw) {
    if (raw == null) return '-';
    final dt = DateTime.tryParse(raw)?.toLocal();
    if (dt == null) return '-';
    return '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')}/'
        '${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _DrawerHeader extends StatelessWidget {
  final VoidCallback onClose;
  const _DrawerHeader({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: VeraProbColors.border.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Detalhes da Justificativa',
            style: VeraProbTypography.sectionTitle,
          ),
          IconButton(icon: const Icon(Icons.close), onPressed: onClose),
        ],
      ),
    );
  }
}

class _InfoField extends StatelessWidget {
  final String label;
  final String value;
  const _InfoField({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: VeraProbTypography.caption.copyWith(
              color: VeraProbColors.textSecondary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(value, style: VeraProbTypography.bodyMedium),
        ],
      ),
    );
  }
}

extension on JustificationStatus {
  bool get isPending => this == JustificationStatus.pending;
}

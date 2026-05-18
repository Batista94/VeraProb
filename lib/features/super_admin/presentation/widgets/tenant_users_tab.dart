import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:veraprob/application/super_admin/tenant_health_view.dart';
import 'package:veraprob/core/theme/app_theme.dart';

import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/super_admin_providers.dart';
import 'package:veraprob/state/providers/shared_providers.dart';

class TenantUsersTab extends ConsumerStatefulWidget {
  final TenantHealthView tenant;
  const TenantUsersTab({super.key, required this.tenant});

  @override
  ConsumerState<TenantUsersTab> createState() => _TenantUsersTabState();
}

class _TenantUsersTabState extends ConsumerState<TenantUsersTab> {
  List<Map<String, dynamic>>? _members;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  @override
  void didUpdateWidget(covariant TenantUsersTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // INV-11: Recarrega membros ao navegar para outro tenant.
    if (oldWidget.tenant.id != widget.tenant.id) {
      _loadMembers();
    }
  }

  Future<void> _loadMembers() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(superAdminRepositoryProvider);
      final members = await repo.getTenantMembers(widget.tenant.id);
      if (mounted) {
        setState(() {
          _members = members;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _toggleStatus(
    String userId,
    bool currentStatus,
    String email,
  ) async {
    final newStatus = !currentStatus;
    try {
      final repo = ref.read(superAdminRepositoryProvider);
      await repo.toggleTenantMemberStatus(
        orgId: widget.tenant.id,
        userId: userId,
        isActive: newStatus,
      );

      // INV-21: Registra STATUS_CHANGE no audit log de governança.
      // 'context' fica fora do before/after para aparecer como campo fixo
      // no AuditPayloadDiffView (não é silenciado pelo filtro de diff).
      final auditSvc = ref.read(systemAuditLogServiceProvider);
      await auditSvc.logGovernanceChange(
        eventType: 'STATUS_CHANGE',
        reason: newStatus
            ? 'Admin reativado pelo SuperAdmin'
            : 'Admin inativado pelo SuperAdmin',

        organizationId: widget.tenant.id,
        organizationName: widget.tenant.name,
        context: {'user_id': userId, 'email': email},
        oldSnapshot: {'is_active': currentStatus},
        newSnapshot: {'is_active': newStatus},
        source: 'tenant_users_tab',
      );

      if (mounted) {
        // INV-22: Invalida snapshot para sincronizar status do painel pai.
        ref.invalidate(tenantHealthSnapshotProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              currentStatus ? 'Usuário inativado.' : 'Usuário reativado.',
            ),
            backgroundColor: VeraProbColors.success,
          ),
        );
      }
      await _loadMembers();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: $e'),
            backgroundColor: VeraProbColors.error,
          ),
        );
      }
    }
  }

  Future<String?> _askReason(BuildContext ctx, String title) async {
    final ctrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<String>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 400,
          child: Form(
            key: formKey,
            child: TextFormField(
              controller: ctrl,
              decoration: const InputDecoration(
                labelText: 'Justificativa',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Obrigatório.' : null,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.of(ctx).pop(ctrl.text.trim());
              }
            },
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    return result;
  }

  Future<void> _resendInvite(String email) async {
    final reason = await _askReason(context, 'Reenviar Convite');
    if (reason == null || !mounted) return;

    try {
      final repo = ref.read(superAdminRepositoryProvider);
      await repo.resendInvitation(
        email: email,
        orgName: widget.tenant.name,
        orgId: widget.tenant.id,
        reason: reason,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Convite reenviado.'),
            backgroundColor: VeraProbColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao reenviar: $e'),
            backgroundColor: VeraProbColors.error,
          ),
        );
      }
    }
  }

  Future<void> _revokeInvite(String email) async {
    final reason = await _askReason(context, 'Revogar Convite');
    if (reason == null || !mounted) return;

    try {
      final repo = ref.read(superAdminRepositoryProvider);
      final userId = ref.read(authStateProvider).value?.session?.user.id ?? '';
      await repo.revokeInvitation(
        orgId: widget.tenant.id,
        email: email,
        superAdminUserId: userId,
        reason: reason,
      );
      if (mounted) {
        // INV-22: Invalida snapshot para sincronizar status do painel pai.
        ref.invalidate(tenantHealthSnapshotProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Convite revogado.'),
            backgroundColor: VeraProbColors.success,
          ),
        );
      }
      await _loadMembers();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao revogar: $e'),
            backgroundColor: VeraProbColors.error,
          ),
        );
      }
    }
  }

  Future<void> _addAdmin() async {
    final emailCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    // INV-22 / Lesson #4: dialog gerencia submit/erro internamente.
    // Só fecha em sucesso — em falha de rede/duplicidade o usuário mantém o
    // contexto digitado e vê a mensagem inline + snackbar.
    final result = await showDialog<({String email, String reason})>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        var submitting = false;
        String? serverError;

        return StatefulBuilder(
          builder: (sbCtx, setSbState) {
            Future<void> submit() async {
              if (!(formKey.currentState?.validate() ?? false)) return;
              setSbState(() {
                submitting = true;
                serverError = null;
              });
              final emailValue = emailCtrl.text.trim();
              final reasonValue = reasonCtrl.text.trim();
              try {
                final repo = ref.read(superAdminRepositoryProvider);
                final userId =
                    ref.read(authStateProvider).value?.session?.user.id ?? '';
                const uuid = Uuid();
                final now = ref.read(dateTimeProviderProvider).nowUtc();
                await repo.addAdminToOrganization(
                  orgId: widget.tenant.id,
                  email: emailValue,
                  invitationId: uuid.v4(),
                  token: uuid.v4(),
                  expiresAtUtc: now.add(const Duration(days: 7)),
                  superAdminUserId: userId,
                  reason: reasonValue,
                );
                if (dialogCtx.mounted) {
                  Navigator.of(
                    dialogCtx,
                  ).pop((email: emailValue, reason: reasonValue));
                }
              } catch (e) {
                // INV-10: Não silencia falhas. Mantém modal aberto para retry
                // — mensagem inline preserva contexto digitado (INV-22).
                if (!dialogCtx.mounted) return;
                setSbState(() {
                  submitting = false;
                  serverError = e
                      .toString()
                      .replaceAll(RegExp(r'^.*Exception: '), '')
                      .trim();
                });
              }
            }

            return AlertDialog(
              title: const Text('Adicionar Administrador'),
              content: SizedBox(
                width: 400,
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: emailCtrl,
                        enabled: !submitting,
                        decoration: const InputDecoration(
                          labelText: 'E-mail do Administrador',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.emailAddress,
                        autofocus: true,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'E-mail obrigatório.';
                          }
                          final emailRegex = RegExp(
                            r'^[\w.+\-]+@[\w\-]+\.[a-z]{2,}',
                          );
                          if (!emailRegex.hasMatch(v.trim())) {
                            return 'E-mail inválido.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: reasonCtrl,
                        enabled: !submitting,
                        decoration: const InputDecoration(
                          labelText: 'Justificativa',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Justificativa obrigatória.';
                          }
                          return null;
                        },
                      ),
                      if (serverError != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          serverError!,
                          style: const TextStyle(
                            color: VeraProbColors.error,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: submitting
                      ? null
                      : () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: submitting ? null : submit,
                  child: submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Convidar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null || !mounted) return;

    // INV-22: Invalida snapshot para sincronizar status do painel pai.
    ref.invalidate(tenantHealthSnapshotProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Convite enviado para ${result.email}.'),
        backgroundColor: VeraProbColors.success,
      ),
    );
    await _loadMembers();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  'Administradores',
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              if (!widget.tenant.isArchived)
                Tooltip(
                  message: 'Adicionar Administrador',
                  child: FilledButton.icon(
                    onPressed: _addAdmin,
                    icon: const Icon(Icons.person_add_outlined, size: 16),
                    label: const Text('Adicionar'),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(child: _buildContent()),
      ],
    );
  }

  Widget _buildContent() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Erro ao carregar usuários',
              style: TextStyle(color: VeraProbColors.error),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _loadMembers,
              child: const Text('Tentar novamente'),
            ),
          ],
        ),
      );
    }
    if (_members == null || _members!.isEmpty) {
      final message = widget.tenant.isArchived
          ? 'Nenhum usuário ou convite pendente encontrado nesta organização arquivada.'
          : 'Nenhum usuário ou convite pendente encontrado.\nUse o botão acima para adicionar um administrador.';
      return Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: VeraProbColors.textSecondary),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      itemCount: _members!.length,
      separatorBuilder: (_, _) => const Divider(),
      itemBuilder: (context, index) {
        final m = _members![index];
        final bool isActive = m['is_active'] as bool? ?? false;
        final String email = m['email'] as String? ?? '';
        final String role = m['role'] as String? ?? '';
        final String status = m['status'] as String? ?? 'inactive';
        final hasSignedIn = m['last_sign_in'] != null;
        final bool isPending = status == 'pending';
        final userId = m['user_id'] as String?;
        final String? inviteToken = m['token'] as String?;
        final bool isOrgArchived = widget.tenant.isArchived;

        return ListTile(
          leading: CircleAvatar(
            radius: 16,
            backgroundColor: isPending
                ? VeraProbColors.warning.withValues(alpha: 0.15)
                : isActive
                ? VeraProbColors.success.withValues(alpha: 0.15)
                : VeraProbColors.error.withValues(alpha: 0.1),
            child: Icon(
              isPending
                  ? Icons.schedule_outlined
                  : isActive
                  ? Icons.person_outlined
                  : Icons.person_off_outlined,
              size: 16,
              color: isPending
                  ? VeraProbColors.warning
                  : isActive
                  ? VeraProbColors.success
                  : VeraProbColors.error,
            ),
          ),
          title: Row(
            children: [
              Flexible(child: Text(email, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              _StatusChip(status: status),
            ],
          ),
          subtitle: Text(
            'Role: $role | Login: ${(status.toLowerCase() == 'active' && hasSignedIn) ? 'Sim' : 'Não'}',
            style: const TextStyle(fontSize: 11),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isPending && inviteToken != null)
                IconButton(
                  icon: const Icon(Icons.copy_outlined, size: 18),
                  tooltip: 'Copiar link de convite',
                  onPressed: () {
                    final link =
                        '${Uri.base.origin}/accept-invite?token=$inviteToken';
                    Clipboard.setData(ClipboardData(text: link));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Link de convite copiado.')),
                    );
                  },
                ),
              if (isPending && !isOrgArchived)
                IconButton(
                  icon: const Icon(Icons.cancel_outlined, size: 18),
                  tooltip: 'Revogar Convite',
                  color: VeraProbColors.error,
                  onPressed: () => _revokeInvite(email),
                ),
              if ((isPending || !hasSignedIn) && !isOrgArchived)
                IconButton(
                  icon: const Icon(Icons.send_outlined, size: 18),
                  tooltip: 'Reenviar Convite',
                  onPressed: () => _resendInvite(email),
                ),
              if (!isPending && userId != null && !isOrgArchived)
                IconButton(
                  icon: Icon(
                    isActive ? Icons.block : Icons.check_circle_outline,
                    size: 18,
                  ),
                  tooltip: isActive ? 'Inativar Usuário' : 'Reativar Usuário',
                  color: isActive
                      ? VeraProbColors.error
                      : VeraProbColors.success,
                  onPressed: () => _toggleStatus(userId, isActive, email),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'active' => ('Ativo', VeraProbColors.success),
      'pending' => ('Pendente', VeraProbColors.warning),
      _ => ('Inativo', VeraProbColors.error),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

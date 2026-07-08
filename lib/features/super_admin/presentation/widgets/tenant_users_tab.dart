import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:veraprob/application/super_admin/tenant_health_view.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/features/super_admin/presentation/widgets/reason_confirmation_dialog.dart';
import 'package:veraprob/features/shared/widgets/invitation_action_buttons.dart';

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
  bool _processing = false;

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
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Falha ao carregar os usuários.';
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
    if (_processing) return;
    final newStatus = !currentStatus;
    final messenger = ScaffoldMessenger.of(context);

    // Apenas exigir justificativa/confirmação ao desativar o usuário (Req 3.3)
    String? reason;
    if (!newStatus) {
      setState(() => _processing = true);
      try {
        reason = await showDialog<String>(
          context: context,
          barrierDismissible: false,
          builder: (_) => ReasonConfirmationDialog(
            title: 'Inativar Usuário',
            promptMessage:
                'Informe a justificativa para inativar o usuário $email.',
          ),
        );
      } finally {
        if (reason == null && mounted) {
          setState(() => _processing = false);
        }
      }
      if (reason == null) return; // SuperAdmin cancelou o modal
    } else {
      setState(() => _processing = true);
      reason = 'Admin reativado pelo SuperAdmin';
    }

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
        reason: reason,
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
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              currentStatus ? 'Usuário inativado.' : 'Usuário reativado.',
            ),
            backgroundColor: VeraProbColors.success,
          ),
        );
      }
      await _loadMembers();
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Falha ao alterar o status do usuário.'),
            backgroundColor: VeraProbColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _processing = false);
      }
    }
  }

  Future<void> _resendInvite(String email) async {
    if (_processing) return;
    setState(() => _processing = true);
    final messenger = ScaffoldMessenger.of(context);
    String? reason;
    try {
      reason = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ReasonConfirmationDialog(
          title: 'Reenviar Convite',
          promptMessage:
              'Informe a justificativa para reenviar o convite para $email.',
        ),
      );
    } finally {
      if (reason == null && mounted) {
        setState(() => _processing = false);
      }
    }
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
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Convite reenviado.'),
            backgroundColor: VeraProbColors.success,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Falha ao reenviar o convite.'),
            backgroundColor: VeraProbColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _processing = false);
      }
    }
  }

  Future<void> _revokeInvite(String email) async {
    if (_processing) return;
    setState(() => _processing = true);
    final messenger = ScaffoldMessenger.of(context);
    String? reason;
    try {
      reason = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ReasonConfirmationDialog(
          title: 'Revogar Convite',
          promptMessage:
              'Informe a justificativa para revogar o convite para $email.',
        ),
      );
    } finally {
      if (reason == null && mounted) {
        setState(() => _processing = false);
      }
    }
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
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Convite revogado.'),
            backgroundColor: VeraProbColors.success,
          ),
        );
      }
      await _loadMembers();
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Falha ao revogar o convite.'),
            backgroundColor: VeraProbColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _processing = false);
      }
    }
  }

  Future<void> _addAdmin() async {
    if (_processing) return;
    setState(() => _processing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
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
                } catch (_) {
                  if (!dialogCtx.mounted) return;
                  setSbState(() {
                    submitting = false;
                    serverError =
                        'Falha ao adicionar administrador. Tente novamente.';
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
                            style: VeraProbTypography.bodySmall.copyWith(
                              color: VeraProbColors.error,
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
      messenger.showSnackBar(
        SnackBar(
          content: Text('Convite enviado para ${result.email}.'),
          backgroundColor: VeraProbColors.success,
        ),
      );
      await _loadMembers();
    } finally {
      if (mounted) {
        setState(() => _processing = false);
      }
    }
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
                      textStyle: VeraProbTypography.bodySmall,
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
            Text(
              'Erro ao carregar usuários',
              style: VeraProbTypography.bodyMedium.copyWith(
                color: VeraProbColors.error,
              ),
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
          style: VeraProbTypography.bodyMedium.copyWith(
            color: VeraProbColors.textSecondary,
          ),
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
        final bool hasLoggedIn =
            status.toLowerCase() == 'active' && hasSignedIn;

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
            'Role: $role | Login: ${hasLoggedIn ? 'Sim' : 'Não'}',
            style: VeraProbTypography.caption,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isPending && inviteToken != null)
                InvitationActionButtons(
                  token: inviteToken,
                  onResend: () => _resendInvite(email),
                  onRevoke: () => _revokeInvite(email),
                  isDisabled: isOrgArchived,
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
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                  style: IconButton.styleFrom(
                    minimumSize: Size.zero,
                    padding: const EdgeInsets.all(4),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
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
        borderRadius: VeraProbRadii.smAll,
      ),
      child: Text(
        label,
        style: VeraProbTypography.badge.copyWith(color: color),
      ),
    );
  }
}

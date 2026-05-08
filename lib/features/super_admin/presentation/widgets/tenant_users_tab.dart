import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:veraprob/application/super_admin/tenant_health_view.dart';
import 'package:veraprob/core/theme/app_theme.dart';

import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/super_admin_providers.dart';

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

  Future<void> _resendInvite(String email) async {
    try {
      final repo = ref.read(superAdminRepositoryProvider);
      await repo.resendInvitation(email: email, orgName: widget.tenant.name);
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Revogar Convite'),
        content: Text('Revogar o convite pendente para $email?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: VeraProbColors.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Revogar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final repo = ref.read(superAdminRepositoryProvider);
      final userId = ref.read(authStateProvider).value?.session?.user.id ?? '';
      await repo.revokeInvitation(
        orgId: widget.tenant.id,
        email: email,
        superAdminUserId: userId,
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
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Adicionar Administrador'),
        content: SizedBox(
          width: 400,
          child: Form(
            key: formKey,
            child: TextFormField(
              controller: emailCtrl,
              decoration: const InputDecoration(
                labelText: 'E-mail do Administrador',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
              autofocus: true,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'E-mail obrigatório.';
                final emailRegex = RegExp(r'^[\w.+\-]+@[\w\-]+\.[a-z]{2,}');
                if (!emailRegex.hasMatch(v.trim())) return 'E-mail inválido.';
                return null;
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.of(context).pop(true);
              }
            },
            child: const Text('Convidar'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final repo = ref.read(superAdminRepositoryProvider);
      final userId = ref.read(authStateProvider).value?.session?.user.id ?? '';
      const uuid = Uuid();
      await repo.addAdminToOrganization(
        orgId: widget.tenant.id,
        email: emailCtrl.text.trim(),
        invitationId: uuid.v4(),
        token: uuid.v4(),
        expiresAtUtc: DateTime.now().toUtc().add(const Duration(days: 7)),
        superAdminUserId: userId,
      );
      if (mounted) {
        // INV-22: Invalida snapshot para sincronizar status do painel pai.
        ref.invalidate(tenantHealthSnapshotProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Convite enviado para ${emailCtrl.text.trim()}.'),
            backgroundColor: VeraProbColors.success,
          ),
        );
      }
      await _loadMembers();
    } catch (e) {
      // INV-10: Não silencia falhas. 'on Exception' mascarava DomainException.
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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Administradores',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              if (!widget.tenant.isArchived)
                FilledButton.icon(
                  onPressed: _addAdmin,
                  icon: const Icon(Icons.person_add_outlined, size: 16),
                  label: const Text('Adicionar Administrador'),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    textStyle: const TextStyle(fontSize: 12),
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
      return const Center(
        child: Text(
          'Nenhum usuário ou convite pendente encontrado.\nUse o botão acima para adicionar um administrador.',
          textAlign: TextAlign.center,
          style: TextStyle(color: VeraProbColors.textSecondary),
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

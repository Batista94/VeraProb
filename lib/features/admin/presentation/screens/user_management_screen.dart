import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../state/providers/admin_providers.dart';
import '../../../../state/providers/auth_providers.dart';
import '../../../../domain/admin/invitation.dart';
import '../../../../domain/enums/user_role.dart';
import '../../../../application/admin/change_user_role_command.dart';
import '../../../../application/admin/remove_member_command.dart';
import '../../../../application/admin/invite_user_command.dart';
import '../../../../application/admin/revoke_invitation_command.dart';

/// Screen for managing organization members and their roles.
/// Also shows pending invitations and allows sending new invites.
class UserManagementScreen extends ConsumerWidget {
  const UserManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(orgMembersProvider);
    final invitationsAsync = ref.watch(orgInvitationsProvider);
    final currentUserId = ref.watch(currentOperatorIdProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.people_outline,
                  size: 28,
                  color: PactaFlowColors.primary,
                ),
                const SizedBox(width: 12),
                Text(
                  'Gestão de Usuários',
                  style: PactaFlowTypography.sectionTitle,
                ),
                const Spacer(),
                FilledButton.icon(
                  icon: const Icon(Icons.person_add_outlined, size: 18),
                  label: const Text('Convidar'),
                  onPressed: () => _showInviteDialog(context, ref),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Gerencie os membros da sua organização e suas permissões de acesso.',
              style: PactaFlowTypography.bodyMedium.copyWith(
                color: PactaFlowColors.textSecondary,
              ),
            ),
            const SizedBox(height: 32),
            Expanded(
              child: ListView(
                children: [
                  // ── Active members ───────────────────────────────────────
                  membersAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(
                      child: Text(
                        'Erro ao carregar membros: $e',
                        style: const TextStyle(color: PactaFlowColors.error),
                      ),
                    ),
                    data: (members) => Column(
                      children: List.generate(members.length * 2 - 1, (i) {
                        if (i.isOdd)
                          return const Divider(color: PactaFlowColors.border);
                        final member = members[i ~/ 2];
                        final isSelf = member.userId == currentUserId;
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: PactaFlowColors.primary.withValues(
                              alpha: 0.1,
                            ),
                            child: Text(
                              member.email[0].toUpperCase(),
                              style: const TextStyle(
                                color: PactaFlowColors.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Text(
                            member.email,
                            style: PactaFlowTypography.kpiLabel,
                          ),
                          subtitle: Text(
                            'Convidado em: ${member.invitedAt.toLocal().toString().split('.')[0]}',
                            style: PactaFlowTypography.caption,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!isSelf)
                                DropdownButton<String>(
                                  value: member.role,
                                  underline: const SizedBox(),
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'TENANT_ADMIN',
                                      child: Text('Administrador'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'OPERATOR',
                                      child: Text('Operador'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'AUDITOR',
                                      child: Text('Auditor'),
                                    ),
                                  ],
                                  onChanged: (newRole) => _changeRole(
                                    context,
                                    ref,
                                    member.userId,
                                    newRole!,
                                  ),
                                )
                              else
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: PactaFlowColors.surface,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: PactaFlowColors.border,
                                    ),
                                  ),
                                  child: const Text(
                                    'Você (Admin)',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              const SizedBox(width: 16),
                              if (!isSelf)
                                IconButton(
                                  icon: const Icon(
                                    Icons.person_remove_outlined,
                                    color: PactaFlowColors.error,
                                    size: 20,
                                  ),
                                  tooltip: 'Remover membro',
                                  onPressed: () => _confirmRemove(
                                    context,
                                    ref,
                                    member.userId,
                                    member.email,
                                  ),
                                ),
                            ],
                          ),
                        );
                      }),
                    ),
                  ),

                  // ── Pending invitations ──────────────────────────────────
                  invitationsAsync.when(
                    loading: () => const SizedBox.shrink(),
                    error: (err, st) => const SizedBox.shrink(),
                    data: (invitations) {
                      final pending = invitations
                          .where((i) => i.isActive)
                          .toList();
                      if (pending.isEmpty) return const SizedBox.shrink();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 32),
                          const Divider(color: PactaFlowColors.border),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              const Icon(
                                Icons.mail_outline,
                                size: 20,
                                color: PactaFlowColors.textSecondary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Convites Pendentes (${pending.length})',
                                style: PactaFlowTypography.kpiLabel,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ...pending.map(
                            (inv) => _PendingInvitationTile(
                              invitation: inv,
                              onRevoke: () =>
                                  _revokeInvitation(context, ref, inv),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showInviteDialog(BuildContext context, WidgetRef ref) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _InviteUserDialog(parentRef: ref),
    );
  }

  Future<void> _changeRole(
    BuildContext context,
    WidgetRef ref,
    String userId,
    String newRoleString,
  ) async {
    try {
      final orgId = ref.read(currentOrganizationIdProvider);
      final callerRole = ref.read(currentUserRoleProvider);

      UserRole newRole;
      if (newRoleString == 'TENANT_ADMIN') {
        newRole = UserRole.admin;
      } else if (newRoleString == 'OPERATOR') {
        newRole = UserRole.operator;
      } else {
        newRole = UserRole.auditor;
      }

      await ref
          .read(changeUserRoleHandlerProvider)
          .handle(
            ChangeUserRoleCommand(
              organizationId: orgId!,
              callerRole: callerRole,
              targetUserId: userId,
              newRole: newRole,
            ),
          );
      ref.invalidate(orgMembersProvider);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Permissão atualizada.'),
            backgroundColor: PactaFlowColors.success,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: $e'),
            backgroundColor: PactaFlowColors.error,
          ),
        );
      }
    }
  }

  Future<void> _confirmRemove(
    BuildContext context,
    WidgetRef ref,
    String userId,
    String email,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remover Membro'),
        content: Text(
          'Deseja realmente remover o usuário $email da organização? Esta ação removerá todo o acesso dele.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: PactaFlowColors.error),
            child: const Text('Remover'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final orgId = ref.read(currentOrganizationIdProvider);
        final callerRole = ref.read(currentUserRoleProvider);

        await ref
            .read(removeMemberHandlerProvider)
            .handle(
              RemoveMemberCommand(
                organizationId: orgId!,
                callerRole: callerRole,
                targetUserId: userId,
              ),
            );
        ref.invalidate(orgMembersProvider);

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Membro removido.'),
              backgroundColor: PactaFlowColors.success,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(e.toString().replaceAll('Exception: ', '')),
              backgroundColor: PactaFlowColors.error,
            ),
          );
        }
      }
    }
  }

  Future<void> _revokeInvitation(
    BuildContext context,
    WidgetRef ref,
    Invitation invitation,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revogar Convite'),
        content: Text(
          'Deseja revogar o convite enviado para ${invitation.email}? O link ficará inválido imediatamente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: PactaFlowColors.error),
            child: const Text('Revogar'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final orgId = ref.read(currentOrganizationIdProvider);
        final callerRole = ref.read(currentUserRoleProvider);

        await ref
            .read(revokeInvitationHandlerProvider)
            .handle(
              RevokeInvitationCommand(
                organizationId: orgId!,
                callerRole: callerRole,
                invitationId: invitation.id,
              ),
            );
        ref.invalidate(orgInvitationsProvider);

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Convite revogado.'),
              backgroundColor: PactaFlowColors.success,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erro: $e'),
              backgroundColor: PactaFlowColors.error,
            ),
          );
        }
      }
    }
  }
}

// ── Pending invitation tile ──────────────────────────────────────────────────

class _PendingInvitationTile extends StatelessWidget {
  final Invitation invitation;
  final VoidCallback onRevoke;

  const _PendingInvitationTile({
    required this.invitation,
    required this.onRevoke,
  });

  @override
  Widget build(BuildContext context) {
    final roleLabel = switch (invitation.role) {
      UserRole.admin => 'Administrador',
      UserRole.operator => 'Operador',
      UserRole.auditor => 'Auditor',
      UserRole.contractorViewer => 'Visualizador Contratante',
    };
    final expiryStr = invitation.expiresAtUtc.toLocal().toString().split(
      '.',
    )[0];

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: PactaFlowColors.warning.withValues(alpha: 0.1),
        child: const Icon(
          Icons.hourglass_empty_outlined,
          color: PactaFlowColors.warning,
          size: 18,
        ),
      ),
      title: Text(invitation.email, style: PactaFlowTypography.kpiLabel),
      subtitle: Text(
        '$roleLabel · Expira em: $expiryStr',
        style: PactaFlowTypography.caption,
      ),
      trailing: IconButton(
        icon: const Icon(
          Icons.cancel_outlined,
          color: PactaFlowColors.error,
          size: 20,
        ),
        tooltip: 'Revogar convite',
        onPressed: onRevoke,
      ),
    );
  }
}

// ── Invite user dialog ───────────────────────────────────────────────────────

class _InviteUserDialog extends ConsumerStatefulWidget {
  final WidgetRef parentRef;

  const _InviteUserDialog({required this.parentRef});

  @override
  ConsumerState<_InviteUserDialog> createState() => _InviteUserDialogState();
}

class _InviteUserDialogState extends ConsumerState<_InviteUserDialog> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  UserRole _selectedRole = UserRole.operator;
  bool _loading = false;
  String? _generatedToken;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_generatedToken != null) {
      return _buildLinkDialog(context);
    }
    return _buildFormDialog(context);
  }

  Widget _buildFormDialog(BuildContext context) {
    return AlertDialog(
      title: const Text('Convidar Usuário'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'E-mail',
                  hintText: 'usuario@empresa.com',
                ),
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Informe o e-mail.';
                  if (!v.contains('@')) return 'E-mail inválido.';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<UserRole>(
                initialValue: _selectedRole,
                decoration: const InputDecoration(labelText: 'Perfil'),
                items: const [
                  DropdownMenuItem(
                    value: UserRole.admin,
                    child: Text('Administrador'),
                  ),
                  DropdownMenuItem(
                    value: UserRole.operator,
                    child: Text('Operador'),
                  ),
                  DropdownMenuItem(
                    value: UserRole.auditor,
                    child: Text('Auditor'),
                  ),
                ],
                onChanged: (r) => setState(() => _selectedRole = r!),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Enviar Convite'),
        ),
      ],
    );
  }

  Widget _buildLinkDialog(BuildContext context) {
    final inviteUrl = '${Uri.base.origin}/accept-invite?token=$_generatedToken';
    return AlertDialog(
      title: const Text('Convite Gerado'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Compartilhe o link abaixo com o usuário convidado:'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: PactaFlowColors.surface,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: PactaFlowColors.border),
              ),
              child: SelectableText(
                inviteUrl,
                style: PactaFlowTypography.caption,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'O link expira em 7 dias.',
              style: PactaFlowTypography.caption.copyWith(
                color: PactaFlowColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.copy_outlined, size: 16),
          label: const Text('Copiar Link'),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: inviteUrl));
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Link copiado!')));
          },
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fechar'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      final orgId = widget.parentRef.read(currentOrganizationIdProvider);
      final callerRole = widget.parentRef.read(currentUserRoleProvider);
      final userId = widget.parentRef.read(currentOperatorIdProvider);

      final token = await ref
          .read(inviteUserHandlerProvider)
          .handle(
            InviteUserCommand(
              organizationId: orgId!,
              callerRole: callerRole,
              invitedByUserId: userId ?? '',
              email: _emailController.text,
              roleToAssign: _selectedRole,
            ),
          );

      widget.parentRef.invalidate(orgInvitationsProvider);
      setState(() {
        _generatedToken = token;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: $e'),
            backgroundColor: PactaFlowColors.error,
          ),
        );
      }
    }
  }
}

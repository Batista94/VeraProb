import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:intl/intl.dart';

import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/state/providers/admin_providers.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/shared_providers.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/application/admin/access_management_service.dart';
import 'package:veraprob/state/providers/access_providers.dart';
import 'package:veraprob/application/admin/change_user_role_command.dart';
import 'package:veraprob/application/admin/remove_member_command.dart';
import 'package:veraprob/application/admin/invite_user_command.dart';
import 'package:veraprob/application/admin/revoke_invitation_command.dart';

/// Screen for managing organization members and their roles.
/// Also shows pending invitations and allows sending new invites.
class UserManagementTab extends ConsumerWidget {
  const UserManagementTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(orgMembersProvider);
    final invitationsAsync = ref.watch(orgInvitationsProvider);
    final currentUserId = ref.watch(currentOperatorIdProvider);
    final canManageAccess = ref
        .watch(permissionServiceProvider)
        .hasPermission('roles:manage');

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.people_outline,
                size: 28,
                color: VeraProbColors.primary,
              ),
              const SizedBox(width: 12),
              Text('Gestão de Equipe', style: VeraProbTypography.sectionTitle),
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
            style: VeraProbTypography.bodyMedium.copyWith(
              color: VeraProbColors.textSecondary,
            ),
          ),
          const SizedBox(height: 32),
          Expanded(
            child: ListView(
              children: [
                switch (membersAsync) {
                  AsyncData(:final value) =>
                    value.isEmpty
                        ? const SizedBox.shrink()
                        : Column(
                            children: List.generate(value.length * 2 - 1, (i) {
                              if (i.isOdd) {
                                return const Divider(
                                  color: VeraProbColors.border,
                                );
                              }
                              final member = value[i ~/ 2];
                              final isSelf = member.userId == currentUserId;
                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: VeraProbColors.primary
                                          .withValues(alpha: 0.1),
                                      child: Text(
                                        member.email[0].toUpperCase(),
                                        style: const TextStyle(
                                          color: VeraProbColors.primary,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    title: Text(
                                      member.email,
                                      style: VeraProbTypography.kpiLabel,
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                    subtitle: Text(
                                      'Convidado em: ${member.invitedAt.toLocal().toString().split('.')[0]}',
                                      style: VeraProbTypography.caption,
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (!isSelf)
                                          DropdownButton<UserRole>(
                                            value: member.role,
                                            underline: const SizedBox(),
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
                                              color: VeraProbColors.surface,
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              border: Border.all(
                                                color: VeraProbColors.border,
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
                                              Icons.person_off_outlined,
                                              color: VeraProbColors.warning,
                                              size: 20,
                                            ),
                                            tooltip: 'Inativar membro',
                                            onPressed: () => _confirmDeactivate(
                                              context,
                                              ref,
                                              member.userId,
                                              member.email,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  if (canManageAccess)
                                    _MemberRolesRow(userId: member.userId),
                                ],
                              );
                            }),
                          ),
                  AsyncLoading() => const Center(
                    child: CircularProgressIndicator(),
                  ),
                  AsyncError() => const Center(
                    child: Text(
                      'Não foi possível carregar os membros da organização.',
                      style: TextStyle(color: VeraProbColors.error),
                    ),
                  ),
                },

                switch (invitationsAsync) {
                  AsyncData(:final value) => _buildInvitations(
                    context,
                    ref,
                    value,
                  ),
                  AsyncLoading() => const SizedBox.shrink(),
                  AsyncError() => const SizedBox.shrink(),
                },
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInvitations(
    BuildContext context,
    WidgetRef ref,
    List<Invitation> value,
  ) {
    final nowUtc = ref.read(dateTimeProviderProvider).nowUtc();
    final pending = value.where((i) => i.isActiveAt(nowUtc)).toList();
    if (pending.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 32),
        const Divider(color: VeraProbColors.border),
        const SizedBox(height: 16),
        Row(
          children: [
            const Icon(
              Icons.mail_outline,
              size: 20,
              color: VeraProbColors.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              'Convites Pendentes (${pending.length})',
              style: VeraProbTypography.kpiLabel,
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...pending.map(
          (inv) => _PendingInvitationTile(
            invitation: inv,
            onRevoke: () => _revokeInvitation(context, ref, inv),
          ),
        ),
      ],
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
    UserRole newRole,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final orgId = ref.read(currentOrganizationIdProvider);
      final callerRole = ref.read(currentUserRoleProvider);
      final sessionId = ref.read(currentSessionIdProvider) ?? '';

      if (orgId == null) {
        throw StateError(
          'Organization context unavailable for role: $callerRole',
        );
      }

      await ref
          .read(changeUserRoleHandlerProvider)
          .handle(
            ChangeUserRoleCommand(
              organizationId: orgId,
              callerRole: callerRole,
              targetUserId: userId,
              newRole: newRole,
              sessionId: sessionId,
            ),
          );
      ref.invalidate(orgMembersProvider);

      messenger.showSnackBar(
        const SnackBar(
          content: Text('Permissão atualizada com sucesso.'),
          backgroundColor: VeraProbColors.success,
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Não foi possível atualizar a permissão. Tente novamente.',
          ),
          backgroundColor: VeraProbColors.error,
        ),
      );
    }
  }

  Future<void> _confirmDeactivate(
    BuildContext context,
    WidgetRef ref,
    String userId,
    String email,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Inativar Membro'),
        content: Text(
          'Deseja realmente inativar o usuário $email? '
          'Ele perderá o acesso ao sistema, mas o histórico será preservado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: VeraProbColors.warning,
            ),
            child: const Text('Inativar'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final orgId = ref.read(currentOrganizationIdProvider);
        final callerRole = ref.read(currentUserRoleProvider);
        final sessionId = ref.read(currentSessionIdProvider) ?? '';

        if (orgId == null) {
          throw StateError(
            'Organization context unavailable for role: $callerRole',
          );
        }

        await ref
            .read(deactivateMemberHandlerProvider)
            .handle(
              RemoveMemberCommand(
                organizationId: orgId,
                callerRole: callerRole,
                targetUserId: userId,
                sessionId: sessionId,
              ),
            );
        ref.invalidate(orgMembersProvider);

        messenger.showSnackBar(
          const SnackBar(
            content: Text('Membro inativado com sucesso.'),
            backgroundColor: VeraProbColors.success,
          ),
        );
      } catch (_) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível inativar o membro. Verifique as permissões e tente novamente.',
            ),
            backgroundColor: VeraProbColors.error,
          ),
        );
      }
    }
  }

  Future<void> _revokeInvitation(
    BuildContext context,
    WidgetRef ref,
    Invitation invitation,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
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
            style: TextButton.styleFrom(foregroundColor: VeraProbColors.error),
            child: const Text('Revogar'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final orgId = ref.read(currentOrganizationIdProvider);
        final callerRole = ref.read(currentUserRoleProvider);
        final sessionId = ref.read(currentSessionIdProvider) ?? '';

        if (orgId == null) {
          throw StateError(
            'Organization context unavailable for role: $callerRole',
          );
        }

        await ref
            .read(revokeInvitationHandlerProvider)
            .handle(
              RevokeInvitationCommand(
                organizationId: orgId,
                callerRole: callerRole,
                invitationId: invitation.id,
                sessionId: sessionId,
              ),
            );
        ref.invalidate(orgInvitationsProvider);

        messenger.showSnackBar(
          const SnackBar(
            content: Text('Convite revogado com sucesso.'),
            backgroundColor: VeraProbColors.success,
          ),
        );
      } catch (_) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível revogar o convite. Tente novamente mais tarde.',
            ),
            backgroundColor: VeraProbColors.error,
          ),
        );
      }
    }
  }
}

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
      UserRole.superAdmin => 'Super Administrador',
    };
    final expiryStr = invitation.expiresAtUtc.toLocal().toString().split(
      '.',
    )[0];

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: VeraProbColors.warning.withValues(alpha: 0.1),
        child: const Icon(
          Icons.hourglass_empty_outlined,
          color: VeraProbColors.warning,
          size: 18,
        ),
      ),
      title: Text(
        invitation.email,
        style: VeraProbTypography.kpiLabel,
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      ),
      subtitle: Text(
        '$roleLabel - Expira em: $expiryStr',
        style: VeraProbTypography.caption,
      ),
      trailing: IconButton(
        icon: const Icon(
          Icons.cancel_outlined,
          color: VeraProbColors.error,
          size: 20,
        ),
        tooltip: 'Revogar convite',
        onPressed: onRevoke,
      ),
    );
  }
}

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
              // ACCENT-FILL-CONTRAST: dark foreground on primary fill.
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: VeraProbColors.background,
                  ),
                )
              : const Text('Enviar Convite'),
        ),
      ],
    );
  }

  Widget _buildLinkDialog(BuildContext context) {
    final baseUri = Uri.base;
    final origin = (baseUri.scheme == 'http' || baseUri.scheme == 'https')
        ? baseUri.origin
        : 'http://localhost:3000';
    final inviteUrl = '$origin/accept-invite?token=$_generatedToken';
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
                color: VeraProbColors.surface,
                borderRadius: VeraProbRadii.smAll,
                border: Border.all(color: VeraProbColors.border),
              ),
              child: SelectableText(
                inviteUrl,
                style: VeraProbTypography.caption,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'O link expira em 7 dias.',
              style: VeraProbTypography.caption.copyWith(
                color: VeraProbColors.textSecondary,
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
    final messenger = ScaffoldMessenger.of(context);

    try {
      final orgId = widget.parentRef.read(currentOrganizationIdProvider);
      final callerRole = widget.parentRef.read(currentUserRoleProvider);
      final userId = widget.parentRef.read(currentOperatorIdProvider);
      final sessionId = widget.parentRef.read(currentSessionIdProvider) ?? '';

      final token = await ref
          .read(inviteUserHandlerProvider)
          .handle(
            InviteUserCommand(
              organizationId: orgId!,
              callerRole: callerRole,
              invitedByUserId: userId ?? '',
              email: _emailController.text,
              roleToAssign: _selectedRole,
              sessionId: sessionId,
            ),
          );

      widget.parentRef.invalidate(orgInvitationsProvider);

      try {
        final email = _emailController.text;
        final baseUri = Uri.base;
        final origin = (baseUri.scheme == 'http' || baseUri.scheme == 'https')
            ? baseUri.origin
            : 'http://localhost:3000';
        final inviteUrl = '$origin/accept-invite?token=$token';
        final orgName =
            (await widget.parentRef.read(orgSettingsProvider.future))?.name ??
            '';
        await ref
            .read(adminNotificationRepositoryProvider)
            .notifyInvite(email: email, inviteUrl: inviteUrl, orgName: orgName);
      } on ProviderException catch (_) {
        // Riverpod v3: provider future errors are wrapped in ProviderException.
        // Notification is best-effort; swallow silently.
      } catch (_) {}

      setState(() {
        _generatedToken = token;
        _loading = false;
      });
    } on ProviderException catch (_) {
      // Riverpod v3: unwrap ProviderException to show original error
      if (mounted) {
        setState(() => _loading = false);
      }
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Não foi possível enviar o convite. Ocorreu um erro no provedor de acesso.',
          ),
          backgroundColor: VeraProbColors.error,
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
      }
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Não foi possível enviar o convite. Verifique os dados e tente novamente.',
          ),
          backgroundColor: VeraProbColors.error,
        ),
      );
    }
  }
}

/// Fine-grained access profiles assigned to a member (Pilar 3.1 multi-role).
///
/// Chips = active `tenant_roles`; delete revokes, the trailing action opens the
/// assignment dialog. Visible only to `roles:manage` holders. The RPCs own the
/// subset guard + four-eyes routing — this is convenience UI.
class _MemberRolesRow extends ConsumerWidget {
  final String userId;

  const _MemberRolesRow({required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rolesAsync = ref.watch(tenantRolesProvider);
    final assignmentsAsync = ref.watch(activeRoleAssignmentsProvider);

    final roles = rolesAsync.value ?? const <TenantRole>[];
    if (roles.isEmpty) return const SizedBox.shrink();

    final assignmentByRoleId = <String, RoleAssignment>{
      for (final a in assignmentsAsync.value ?? const <RoleAssignment>[])
        if (a.userId == userId) a.roleId: a,
    };
    final assigned = roles.where((r) => assignmentByRoleId.containsKey(r.id));
    final available = roles.where((r) => !assignmentByRoleId.containsKey(r.id));

    return Padding(
      padding: const EdgeInsets.only(left: 72, right: 16, bottom: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final role in assigned)
            _buildRoleChip(
              context,
              ref,
              role,
              assignmentByRoleId[role.id]!.validUntilUtc,
            ),
          if (available.isNotEmpty)
            ActionChip(
              avatar: const Icon(Icons.add, size: 14),
              label: const Text('Perfil'),
              onPressed: () => _assign(context, ref, available.toList()),
            ),
        ],
      ),
    );
  }

  /// Time-bound assignments render in Amber with the expiry date; permanent
  /// ones keep the primary tint. Foreground stays the semantic color over a
  /// tint (never white over an accent fill — ACCENT-FILL-CONTRAST).
  Widget _buildRoleChip(
    BuildContext context,
    WidgetRef ref,
    TenantRole role,
    DateTime? validUntilUtc,
  ) {
    final expiring = validUntilUtc != null;
    final label = expiring
        ? '${role.name} · até ${DateFormat('dd/MM/yyyy').format(validUntilUtc.toLocal())}'
        : role.name;
    return Chip(
      avatar: expiring
          ? const Icon(
              Icons.schedule_outlined,
              size: 14,
              color: VeraProbColors.warning,
            )
          : null,
      label: Text(
        label,
        style: expiring
            ? VeraProbTypography.caption.copyWith(color: VeraProbColors.warning)
            : VeraProbTypography.caption,
      ),
      backgroundColor: expiring
          ? VeraProbColors.warning.withValues(alpha: 0.12)
          : VeraProbColors.primary.withValues(alpha: 0.1),
      side: expiring
          ? BorderSide(color: VeraProbColors.warning.withValues(alpha: 0.4))
          : null,
      deleteIcon: const Icon(Icons.close, size: 14),
      onDeleted: () => _revoke(context, ref, role),
    );
  }

  Future<void> _assign(
    BuildContext context,
    WidgetRef ref,
    List<TenantRole> available,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await showDialog<_AssignResult>(
      context: context,
      builder: (_) => _AssignRoleDialog(available: available),
    );
    if (result == null) return;
    try {
      await ref
          .read(accessManagementServiceProvider)
          .assignRole(
            userId: userId,
            roleId: result.roleId,
            validUntilUtc: result.validUntilUtc,
          );
      ref.invalidate(activeRoleAssignmentsProvider);
      ref.invalidate(pendingRoleChangesProvider);
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Perfil atribuído. Se sensível, aguarda um segundo administrador.',
          ),
          backgroundColor: VeraProbColors.success,
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Não foi possível atribuir o perfil. Verifique suas permissões e tente novamente.',
          ),
          backgroundColor: VeraProbColors.error,
        ),
      );
    }
  }

  Future<void> _revoke(
    BuildContext context,
    WidgetRef ref,
    TenantRole role,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revogar Perfil de Acesso'),
        content: Text(
          'Deseja revogar o perfil "${role.name}"? O usuário perderá as permissões associadas imediatamente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: VeraProbColors.error),
            child: const Text('Revogar'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await ref
            .read(accessManagementServiceProvider)
            .revokeRole(userId: userId, roleId: role.id);
        ref.invalidate(activeRoleAssignmentsProvider);
        messenger.showSnackBar(
          SnackBar(
            content: Text('Perfil "${role.name}" removido.'),
            backgroundColor: VeraProbColors.success,
          ),
        );
      } catch (_) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível remover o perfil. Tente novamente.',
            ),
            backgroundColor: VeraProbColors.error,
          ),
        );
      }
    }
  }
}

class _AssignResult {
  final String roleId;
  final DateTime? validUntilUtc;
  const _AssignResult(this.roleId, this.validUntilUtc);
}

class _AssignRoleDialog extends StatefulWidget {
  final List<TenantRole> available;
  const _AssignRoleDialog({required this.available});

  @override
  State<_AssignRoleDialog> createState() => _AssignRoleDialogState();
}

class _AssignRoleDialogState extends State<_AssignRoleDialog> {
  late String _roleId = widget.available.first.id;
  DateTime? _validUntilUtc;

  Future<void> _pickDate() async {
    final nowUtc = DateTime.now().toUtc();
    final picked = await showDatePicker(
      context: context,
      firstDate: nowUtc,
      lastDate: nowUtc.add(const Duration(days: 365 * 2)),
      initialDate: _validUntilUtc ?? nowUtc.add(const Duration(days: 30)),
    );
    if (picked != null) {
      setState(() => _validUntilUtc = picked.toUtc());
    }
  }

  @override
  Widget build(BuildContext context) {
    final expiryLabel = _validUntilUtc == null
        ? 'Permanente'
        : 'Até ${DateFormat('dd/MM/yyyy').format(_validUntilUtc!.toLocal())}';
    return AlertDialog(
      title: const Text('Atribuir Perfil de Acesso'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _roleId,
              decoration: const InputDecoration(labelText: 'Perfil'),
              items: [
                for (final r in widget.available)
                  DropdownMenuItem(value: r.id, child: Text(r.name)),
              ],
              onChanged: (v) => setState(() => _roleId = v ?? _roleId),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Validade: $expiryLabel',
                    style: VeraProbTypography.caption,
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.event_outlined, size: 16),
                  label: const Text('Definir'),
                  onPressed: _pickDate,
                ),
                if (_validUntilUtc != null)
                  IconButton(
                    icon: const Icon(Icons.clear, size: 16),
                    tooltip: 'Tornar permanente',
                    onPressed: () => setState(() => _validUntilUtc = null),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, _AssignResult(_roleId, _validUntilUtc)),
          child: const Text('Atribuir'),
        ),
      ],
    );
  }
}

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
import 'package:veraprob/application/admin/user_management_query_service.dart';
import 'package:veraprob/state/providers/access_providers.dart';
import 'package:veraprob/application/admin/remove_member_command.dart';
import 'package:veraprob/application/admin/invite_user_command.dart';
import 'package:veraprob/application/admin/revoke_invitation_command.dart';
import 'package:veraprob/features/shared/widgets/invitation_action_buttons.dart';

enum _StatusFilter { all, active, archived, pending }

/// Coarse trust-root label — fallback when a member has no tenant-role profile
/// (superAdmin, or admin with no custom role assigned).
String _coarseRoleLabel(UserRole role) => switch (role) {
  UserRole.admin => 'Administrador',
  UserRole.operator => 'Operador',
  UserRole.auditor => 'Auditor',
  UserRole.contractorViewer => 'Visualizador',
  UserRole.superAdmin => 'Super Administrador',
};

/// Screen for managing organization members and their access profiles.
///
/// Profiles are unified on tenant roles (Palantir-tier): the `+ Perfil` chips
/// are the single assignment surface, hierarchy-gated so a member can only grant
/// roles fully within their own permission ceiling and cannot manage members who
/// hold permissions they lack — mirroring the DB guards in
/// `assign_tenant_role`/`revoke_tenant_role`. Deactivated members move to the
/// Arquivados section for reactivation/consultation.
class UserManagementTab extends ConsumerStatefulWidget {
  const UserManagementTab({super.key});

  @override
  ConsumerState<UserManagementTab> createState() => _UserManagementTabState();
}

class _UserManagementTabState extends ConsumerState<UserManagementTab> {
  String _emailFilter = '';
  String? _profileFilter; // null = Todos
  _StatusFilter _statusFilter = _StatusFilter.all;

  @override
  Widget build(BuildContext context) {
    final membersAsync = ref.watch(orgMembersProvider);
    final invitationsAsync = ref.watch(orgInvitationsProvider);
    final currentUserId = ref.watch(currentOperatorIdProvider);
    final roles = ref.watch(tenantRolesProvider).value ?? const <TenantRole>[];
    final assignments =
        ref.watch(activeRoleAssignmentsProvider).value ??
        const <RoleAssignment>[];
    final perms = ref.watch(permissionServiceProvider);
    final canManageUsers =
        perms.hasPermission('users:manage') ||
        perms.hasPermission('roles:manage');

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
              if (canManageUsers)
                FilledButton.icon(
                  icon: const Icon(Icons.person_add_outlined, size: 18),
                  label: const Text('Convidar'),
                  onPressed: () => _showInviteDialog(context),
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
          const SizedBox(height: 24),
          _buildFilterBar(roles),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              children: [
                switch (membersAsync) {
                  AsyncData(:final value) =>
                    _statusFilter == _StatusFilter.pending
                        ? const SizedBox.shrink()
                        : _buildMembersSection(
                            context,
                            value,
                            currentUserId,
                            canManageUsers,
                            roles,
                            assignments,
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
                if (canManageUsers)
                  switch (invitationsAsync) {
                    AsyncData(:final value) =>
                      (_statusFilter == _StatusFilter.active ||
                              _statusFilter == _StatusFilter.archived)
                          ? const SizedBox.shrink()
                          : _buildInvitations(context, value, roles),
                    _ => const SizedBox.shrink(),
                  },
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(List<TenantRole> roles) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search, size: 18),
              hintText: 'Filtrar por e-mail',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _emailFilter = v.trim()),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 200,
          child: DropdownButtonFormField<String?>(
            initialValue: _profileFilter,
            isExpanded: true,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Perfil',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Todos'),
              ),
              for (final r in roles)
                DropdownMenuItem<String?>(value: r.name, child: Text(r.name)),
            ],
            onChanged: (v) => setState(() => _profileFilter = v),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 200,
          child: DropdownButtonFormField<_StatusFilter>(
            initialValue: _statusFilter,
            isExpanded: true,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Status',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: _StatusFilter.all, child: Text('Todos')),
              DropdownMenuItem(
                value: _StatusFilter.active,
                child: Text('Ativo'),
              ),
              DropdownMenuItem(
                value: _StatusFilter.archived,
                child: Text('Arquivado'),
              ),
              DropdownMenuItem(
                value: _StatusFilter.pending,
                child: Text('Convite Pendente'),
              ),
            ],
            onChanged: (v) => setState(() => _statusFilter = v!),
          ),
        ),
      ],
    );
  }

  Widget _buildMembersSection(
    BuildContext context,
    List<OrgMember> all,
    String? currentUserId,
    bool canManageUsers,
    List<TenantRole> roles,
    List<RoleAssignment> assignments,
  ) {
    final active = all.where((m) => m.isActive).toList();
    final archived = all.where((m) => !m.isActive).toList();

    final filtered = active.where((m) {
      if (_emailFilter.isNotEmpty &&
          !m.email.toLowerCase().contains(_emailFilter.toLowerCase())) {
        return false;
      }
      if (_profileFilter == null) return true;
      final profile =
          highestPrivilegeRoleName(
            userId: m.userId,
            assignments: assignments,
            roles: roles,
          ) ??
          _coarseRoleLabel(m.role);
      return profile == _profileFilter;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_statusFilter == _StatusFilter.active ||
            _statusFilter == _StatusFilter.all) ...[
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  active.isEmpty
                      ? 'Nenhum membro ativo.'
                      : 'Nenhum membro corresponde ao filtro.',
                  style: VeraProbTypography.bodyMedium.copyWith(
                    color: VeraProbColors.textSecondary,
                  ),
                ),
              ),
            )
          else
            for (int i = 0; i < filtered.length; i++) ...[
              if (i > 0) const Divider(color: VeraProbColors.border),
              _buildMemberTile(
                context,
                filtered[i],
                filtered[i].userId == currentUserId,
                canManageUsers,
                roles,
                assignments,
                currentUserId,
              ),
            ],
        ],
        if (archived.isNotEmpty &&
            (_statusFilter == _StatusFilter.archived ||
                _statusFilter == _StatusFilter.all))
          _buildArchivedSection(context, archived, canManageUsers),
      ],
    );
  }

  Widget _buildMemberTile(
    BuildContext context,
    OrgMember member,
    bool isSelf,
    bool canManageUsers,
    List<TenantRole> roles,
    List<RoleAssignment> assignments,
    String? currentUserId,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          leading: CircleAvatar(
            backgroundColor: VeraProbColors.primary.withValues(alpha: 0.1),
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
              if (isSelf)
                _buildSelfBadge(currentUserId, roles, assignments, member.role)
              else if (canManageUsers)
                IconButton(
                  icon: const Icon(
                    Icons.person_off_outlined,
                    color: VeraProbColors.warning,
                    size: 20,
                  ),
                  tooltip: 'Inativar membro',
                  onPressed: () =>
                      _confirmDeactivate(context, member.userId, member.email),
                ),
            ],
          ),
        ),
        if (canManageUsers) _MemberRolesRow(userId: member.userId),
      ],
    );
  }

  /// Self-badge reflects the logged-in profile (case 3): highest-privilege
  /// tenant role, falling back to the coarse label — never a hardcoded "Admin".
  Widget _buildSelfBadge(
    String? currentUserId,
    List<TenantRole> roles,
    List<RoleAssignment> assignments,
    UserRole coarseRole,
  ) {
    final profile =
        (currentUserId == null
            ? null
            : highestPrivilegeRoleName(
                userId: currentUserId,
                assignments: assignments,
                roles: roles,
              )) ??
        _coarseRoleLabel(coarseRole);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: VeraProbColors.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: VeraProbColors.border),
      ),
      child: Text(
        'Você · $profile',
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
      ),
    );
  }

  /// Deactivated members, retained for reactivation/consultation (case 4).
  Widget _buildArchivedSection(
    BuildContext context,
    List<OrgMember> archived,
    bool canManageUsers,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 32),
        const Divider(color: VeraProbColors.border),
        const SizedBox(height: 16),
        Row(
          children: [
            const Icon(
              Icons.inventory_2_outlined,
              size: 20,
              color: VeraProbColors.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              'Arquivados (${archived.length})',
              style: VeraProbTypography.kpiLabel,
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...archived.map(
          (m) => ListTile(
            leading: CircleAvatar(
              backgroundColor: VeraProbColors.textSecondary.withValues(
                alpha: 0.1,
              ),
              child: Text(
                m.email[0].toUpperCase(),
                style: const TextStyle(
                  color: VeraProbColors.textSecondary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Text(
              m.email,
              style: VeraProbTypography.kpiLabel.copyWith(
                color: VeraProbColors.textSecondary,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
            subtitle: Text(
              'Inativo · ${_coarseRoleLabel(m.role)}',
              style: VeraProbTypography.caption,
            ),
            trailing: canManageUsers
                ? TextButton.icon(
                    icon: const Icon(Icons.restore, size: 16),
                    label: const Text('Reativar'),
                    onPressed: () =>
                        _confirmReactivate(context, m.userId, m.email),
                  )
                : null,
          ),
        ),
      ],
    );
  }

  Widget _buildInvitations(
    BuildContext context,
    List<Invitation> value,
    List<TenantRole> roles,
  ) {
    final nowUtc = ref.read(dateTimeProviderProvider).nowUtc();
    final pending = value.where((i) {
      if (!i.isActiveAt(nowUtc)) return false;
      if (_emailFilter.isNotEmpty &&
          !i.email.toLowerCase().contains(_emailFilter.toLowerCase())) {
        return false;
      }
      if (_profileFilter != null) {
        final profileName = i.tenantRoleId != null
            ? roles
                  .firstWhere(
                    (r) => r.id == i.tenantRoleId,
                    orElse: () => const TenantRole(
                      id: '',
                      name: 'Desconhecido',
                      description: null,
                      isSystem: false,
                      grants: [],
                    ),
                  )
                  .name
            : _coarseRoleLabel(i.role);
        if (profileName != _profileFilter) return false;
      }
      return true;
    }).toList();
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
            onRevoke: () => _revokeInvitation(context, inv),
            onResend: () => _resendInvitation(context, inv),
            roles: roles,
          ),
        ),
      ],
    );
  }

  Future<void> _showInviteDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _InviteUserDialog(parentRef: ref),
    );
  }

  Future<void> _confirmDeactivate(
    BuildContext context,
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
          throw const DomainException('Contexto da organização indisponível.');
        }

        await ref
            .read(deactivateMemberHandlerProvider)
            .handle(
              RemoveMemberCommand(
                organizationId: orgId,
                callerRole: callerRole,
                callerUserId: ref.read(currentOperatorIdProvider) ?? '',
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

  Future<void> _confirmReactivate(
    BuildContext context,
    String userId,
    String email,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reativar Membro'),
        content: Text(
          'Deseja reativar o usuário $email? '
          'Ele voltará a ter acesso ao sistema com seus perfis anteriores.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: VeraProbColors.success,
            ),
            child: const Text('Reativar'),
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
          throw const DomainException('Contexto da organização indisponível.');
        }

        await ref
            .read(reactivateMemberHandlerProvider)
            .handle(
              RemoveMemberCommand(
                organizationId: orgId,
                callerRole: callerRole,
                callerUserId: ref.read(currentOperatorIdProvider) ?? '',
                targetUserId: userId,
                sessionId: sessionId,
              ),
            );
        ref.invalidate(orgMembersProvider);

        messenger.showSnackBar(
          const SnackBar(
            content: Text('Membro reativado com sucesso.'),
            backgroundColor: VeraProbColors.success,
          ),
        );
      } catch (_) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível reativar o membro. Verifique as permissões e tente novamente.',
            ),
            backgroundColor: VeraProbColors.error,
          ),
        );
      }
    }
  }

  Future<void> _resendInvitation(
    BuildContext context,
    Invitation invitation,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final orgId = ref.read(currentOrganizationIdProvider);
      final callerRole = ref.read(currentUserRoleProvider);
      final currentUserId = ref.read(currentOperatorIdProvider);
      final sessionId = ref.read(currentSessionIdProvider) ?? '';

      if (orgId == null || currentUserId == null) {
        throw const DomainException(
          'Contexto da organização ou usuário indisponível.',
        );
      }

      await ref
          .read(inviteUserHandlerProvider)
          .handle(
            InviteUserCommand(
              organizationId: orgId,
              callerRole: callerRole,
              invitedByUserId: currentUserId,
              email: invitation.email,
              roleToAssign: invitation.role,
              sessionId: sessionId,
            ),
          );
      ref.invalidate(orgInvitationsProvider);

      messenger.showSnackBar(
        const SnackBar(
          content: Text('Convite reenviado com sucesso.'),
          backgroundColor: VeraProbColors.success,
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Não foi possível reenviar o convite. Verifique as permissões.',
          ),
          backgroundColor: VeraProbColors.error,
        ),
      );
    }
  }

  Future<void> _revokeInvitation(
    BuildContext context,
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
          throw const DomainException('Contexto da organização indisponível.');
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
  final VoidCallback onResend;
  final List<TenantRole> roles;

  const _PendingInvitationTile({
    required this.invitation,
    required this.onRevoke,
    required this.onResend,
    required this.roles,
  });

  @override
  Widget build(BuildContext context) {
    final roleLabel = invitation.tenantRoleId != null
        ? roles
              .firstWhere(
                (r) => r.id == invitation.tenantRoleId,
                orElse: () => const TenantRole(
                  id: '',
                  name: 'Desconhecido',
                  description: null,
                  isSystem: false,
                  grants: [],
                ),
              )
              .name
        : _coarseRoleLabel(invitation.role);
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
      trailing: InvitationActionButtons(
        token: invitation.token,
        onResend: onResend,
        onRevoke: onRevoke,
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
  String? _selectedTenantRoleId;
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
    // Only '*' holders (system Administrador / superAdmin) may create another
    // Administrador — the option is hidden entirely otherwise (case 2).
    final canInviteAdmin = ref.read(currentPermissionsProvider).contains('*');
    final roles = ref.watch(tenantRolesProvider).value ?? const <TenantRole>[];

    final availableRoles = roles.where((r) {
      if (r.isSystem && r.name == 'Administrador' && !canInviteAdmin) {
        return false;
      }
      return true;
    }).toList();

    // Default to 'Operador' if available
    if (_selectedTenantRoleId == null && availableRoles.isNotEmpty) {
      // Must set without triggering rebuild during build
      _selectedTenantRoleId = availableRoles
          .firstWhere(
            (r) => r.name == 'Operador',
            orElse: () => availableRoles.first,
          )
          .id;
    }

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
              DropdownButtonFormField<String>(
                initialValue: _selectedTenantRoleId,
                decoration: const InputDecoration(labelText: 'Perfil'),
                items: availableRoles.map((r) {
                  return DropdownMenuItem(value: r.id, child: Text(r.name));
                }).toList(),
                onChanged: (id) => setState(() => _selectedTenantRoleId = id),
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

      final roles = ref.read(tenantRolesProvider).value ?? const <TenantRole>[];
      final selectedRoleObj = roles.firstWhere(
        (r) => r.id == _selectedTenantRoleId,
      );
      final derivedCoarseRole =
          (selectedRoleObj.isSystem && selectedRoleObj.name == 'Administrador')
          ? UserRole.admin
          : UserRole.operator;

      final token = await ref
          .read(inviteUserHandlerProvider)
          .handle(
            InviteUserCommand(
              organizationId: orgId!,
              callerRole: callerRole,
              invitedByUserId: userId ?? '',
              email: _emailController.text,
              roleToAssign: derivedCoarseRole,
              tenantRoleId: _selectedTenantRoleId,
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
/// assignment dialog. Hierarchy-gated (case 2): a caller only sees the `+ Perfil`
/// action and delete affordance for roles fully within their own permission
/// ceiling, and the whole row is view-only when the target holds any permission
/// the caller lacks. The RPCs own the authoritative subset + four-eyes guard —
/// this mirrors them for UX so blocked actions never render.
class _MemberRolesRow extends ConsumerWidget {
  final String userId;

  const _MemberRolesRow({required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rolesAsync = ref.watch(tenantRolesProvider);
    final assignmentsAsync = ref.watch(activeRoleAssignmentsProvider);
    final perms = ref.watch(currentPermissionsProvider);

    final roles = rolesAsync.value ?? const <TenantRole>[];
    if (roles.isEmpty) return const SizedBox.shrink();

    final allAssignments = assignmentsAsync.value ?? const <RoleAssignment>[];
    final assignmentByRoleId = <String, RoleAssignment>{
      for (final a in allAssignments)
        if (a.userId == userId) a.roleId: a,
    };
    final assigned = roles
        .where((r) => assignmentByRoleId.containsKey(r.id))
        .toList();

    final isSuper = perms.contains('*');

    // View-only when the target holds any permission the caller lacks
    // (mirrors _rbac_assert_can_manage_target — no managing "up").
    final heldByTarget = memberHeldPermissionKeys(
      userId: userId,
      assignments: allAssignments,
      roles: roles,
    );
    final locked = !isSuper && heldByTarget.any((k) => !perms.contains(k));

    // Caller may grant only roles fully within their own ceiling
    // (mirrors _rbac_assert_can_grant_role — Administrador never appears for a
    // Validador).
    bool canGrant(TenantRole r) =>
        isSuper || r.permissionKeys.every(perms.contains);

    final available = roles
        .where((r) => !assignmentByRoleId.containsKey(r.id) && canGrant(r))
        .toList();

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
              // ponytail: assigned.length > 1 mirrors the LastProfileGuard on
              // the backend -- keeps the X hidden when it would always fail.
              deletable: !locked && canGrant(role) && assigned.length > 1,
            ),
          if (!locked && available.isNotEmpty)
            ActionChip(
              avatar: const Icon(Icons.add, size: 14),
              label: const Text('Perfil'),
              onPressed: () => _assign(context, ref, available),
            ),
        ],
      ),
    );
  }

  /// Time-bound assignments render in Amber with the expiry date; permanent
  /// ones keep the primary tint. Foreground stays the semantic color over a
  /// tint (never white over an accent fill — ACCENT-FILL-CONTRAST). The delete
  /// affordance only renders when the caller may revoke the role.
  Widget _buildRoleChip(
    BuildContext context,
    WidgetRef ref,
    TenantRole role,
    DateTime? validUntilUtc, {
    required bool deletable,
  }) {
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
      deleteIcon: deletable ? const Icon(Icons.close, size: 14) : null,
      onDeleted: deletable ? () => _revoke(context, ref, role) : null,
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
      final isPending = await ref
          .read(accessManagementServiceProvider)
          .assignRole(
            userId: userId,
            roleId: result.roleId,
            validUntilUtc: result.validUntilUtc,
          );
      ref.invalidate(activeRoleAssignmentsProvider);
      ref.invalidate(pendingRoleChangesProvider);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            isPending
                ? 'Perfil sensível: aguarda aprovação de um segundo administrador.'
                : 'Perfil atribuído com sucesso.',
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
      } on DomainException catch (e) {
        final msg = e.message.contains('LastProfileGuard')
            ? 'Não é possível remover o único perfil ativo do usuário.'
            : 'Não foi possível remover o perfil. Tente novamente.';
        messenger.showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: VeraProbColors.error),
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

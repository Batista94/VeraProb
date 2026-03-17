import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../state/providers/admin_providers.dart';
import '../../../../state/providers/auth_providers.dart';
import '../../../../domain/enums/user_role.dart';
import '../../../../application/admin/change_user_role_command.dart';
import '../../../../application/admin/remove_member_command.dart';

/// Screen for managing organization members and their roles.
class UserManagementScreen extends ConsumerWidget {
  const UserManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(orgMembersProvider);
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
                const Icon(Icons.people_outline, size: 28, color: PactaFlowColors.primary),
                const SizedBox(width: 12),
                Text('Gestão de Usuários', style: PactaFlowTypography.sectionTitle),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Gerencie os membros da sua organização e suas permissões de acesso.',
              style: PactaFlowTypography.bodyMedium.copyWith(color: PactaFlowColors.textSecondary),
            ),
            const SizedBox(height: 32),
            Expanded(
              child: membersAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Text(
                    'Erro ao carregar membros: $e',
                    style: const TextStyle(color: PactaFlowColors.error),
                  ),
                ),
                data: (members) {
                  return ListView.separated(
                    itemCount: members.length,
                    separatorBuilder: (_, __) => const Divider(color: PactaFlowColors.border),
                    itemBuilder: (context, index) {
                      final member = members[index];
                      final isSelf = member.userId == currentUserId;
                      
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: PactaFlowColors.primary.withValues(alpha: 0.1),
                          child: Text(
                            member.email[0].toUpperCase(), 
                            style: const TextStyle(color: PactaFlowColors.primary, fontWeight: FontWeight.bold),
                          ),
                        ),
                        title: Text(member.email, style: PactaFlowTypography.kpiLabel),
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
                                  DropdownMenuItem(value: 'TENANT_ADMIN', child: Text('Administrador')),
                                  DropdownMenuItem(value: 'OPERATOR', child: Text('Operador')),
                                  DropdownMenuItem(value: 'AUDITOR', child: Text('Auditor')),
                                ],
                                onChanged: (newRole) => _changeRole(context, ref, member.userId, newRole!),
                              )
                            else
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                  color: PactaFlowColors.surface,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: PactaFlowColors.border),
                                ),
                                child: const Text('Você (Admin)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                              ),
                            const SizedBox(width: 16),
                            if (!isSelf)
                              IconButton(
                                icon: const Icon(Icons.person_remove_outlined, color: PactaFlowColors.error, size: 20),
                                tooltip: 'Remover membro',
                                onPressed: () => _confirmRemove(context, ref, member.userId, member.email),
                              ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _changeRole(BuildContext context, WidgetRef ref, String userId, String newRoleString) async {
    try {
      final orgId = ref.read(currentOrganizationIdProvider);
      final callerRole = ref.read(currentUserRoleProvider);
      
      UserRole newRole;
      if (newRoleString == 'TENANT_ADMIN') newRole = UserRole.admin;
      else if (newRoleString == 'OPERATOR') newRole = UserRole.operator;
      else newRole = UserRole.auditor;

      final command = ChangeUserRoleCommand(
        organizationId: orgId!,
        callerRole: callerRole,
        targetUserId: userId,
        newRole: newRole,
      );

      await ref.read(changeUserRoleHandlerProvider).handle(command);
      ref.invalidate(orgMembersProvider);
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permissão atualizada.'), backgroundColor: PactaFlowColors.success),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: PactaFlowColors.error),
        );
      }
    }
  }

  Future<void> _confirmRemove(BuildContext context, WidgetRef ref, String userId, String email) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remover Membro'),
        content: Text('Deseja realmente remover o usuário $email da organização? Esta ação removerá todo o acesso dele.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
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

        final command = RemoveMemberCommand(
          organizationId: orgId!,
          callerRole: callerRole,
          targetUserId: userId,
        );

        await ref.read(removeMemberHandlerProvider).handle(command);
        ref.invalidate(orgMembersProvider);
        
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Membro removido.'), backgroundColor: PactaFlowColors.success),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: PactaFlowColors.error),
          );
        }
      }
    }
  }
}

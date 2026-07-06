import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:veraprob/application/admin/access_management_service.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/presentation/shared/ui/master_detail_scaffold.dart';
import 'package:veraprob/state/providers/access_providers.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/contract_providers.dart';

/// Access & Profiles management (Pilar 3.1) — visible only with `roles:manage`.
///
/// Master = tenant role catalog; detail = per-module permission matrix editor
/// with ABAC-lite scope; a four-eyes approval queue sits above. All writes route
/// through the SECURITY DEFINER RPCs (subset guard + org scope + sensitive-perm
/// four-eyes live on the DB — this UI is feedback-before-error only).
class AccessManagementTab extends ConsumerStatefulWidget {
  const AccessManagementTab({super.key});

  @override
  ConsumerState<AccessManagementTab> createState() =>
      _AccessManagementTabState();
}

class _AccessManagementTabState extends ConsumerState<AccessManagementTab> {
  String? _selectedRoleId;
  bool _creatingNew = false;

  void _selectRole(String roleId) {
    setState(() {
      _selectedRoleId = roleId;
      _creatingNew = false;
    });
  }

  void _startNewRole() {
    setState(() {
      _creatingNew = true;
      _selectedRoleId = null;
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedRoleId = null;
      _creatingNew = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final rolesAsync = ref.watch(tenantRolesProvider);
    final dictAsync = ref.watch(permissionDictionaryProvider);

    return Padding(
      padding: const EdgeInsets.all(VeraProbSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.admin_panel_settings_outlined,
                size: 24,
                color: VeraProbColors.primary,
              ),
              const SizedBox(width: 12),
              Text('Acessos & Perfis', style: VeraProbTypography.sectionTitle),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Defina perfis de acesso e atribua permissões granulares por módulo.',
            style: VeraProbTypography.bodyMedium.copyWith(
              color: VeraProbColors.textSecondary,
            ),
          ),
          const SizedBox(height: VeraProbSpacing.md),
          const _PendingApprovalsSection(),
          const SizedBox(height: VeraProbSpacing.md),
          Expanded(child: _buildBody(rolesAsync, dictAsync)),
        ],
      ),
    );
  }

  Widget _buildBody(
    AsyncValue<List<TenantRole>> rolesAsync,
    AsyncValue<List<TenantPermission>> dictAsync,
  ) {
    if (rolesAsync.isLoading || dictAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (rolesAsync.hasError || dictAsync.hasError) {
      return const Center(
        child: Text(
          'Não foi possível carregar os perfis de acesso. Tente novamente.',
          style: TextStyle(color: VeraProbColors.error),
        ),
      );
    }
    final roles = rolesAsync.value ?? const <TenantRole>[];
    final dict = dictAsync.value ?? const <TenantPermission>[];

    return MasterDetailScaffold(
      hasSelection: _creatingNew || _selectedRoleId != null,
      onBack: _clearSelection,
      masterBuilder: (_) => _RoleMasterList(
        roles: roles,
        selectedRoleId: _selectedRoleId,
        onSelect: _selectRole,
        onNew: _startNewRole,
      ),
      detailBuilder: (_) => _buildDetail(roles, dict),
    );
  }

  Widget _buildDetail(List<TenantRole> roles, List<TenantPermission> dict) {
    if (_creatingNew) {
      return _RoleMatrixEditor(
        key: const ValueKey('new-role'),
        role: null,
        dictionary: dict,
        onSaved: _clearSelection,
      );
    }
    final matches = roles.where((r) => r.id == _selectedRoleId);
    final role = matches.isEmpty ? null : matches.first;
    if (role == null) {
      return const Center(
        child: Text(
          'Selecione um perfil para editar as permissões.',
          style: TextStyle(color: VeraProbColors.textSecondary),
        ),
      );
    }
    return _RoleMatrixEditor(
      key: ValueKey(role.id),
      role: role,
      dictionary: dict,
      onSaved: _clearSelection,
    );
  }
}

// ── Master: role catalog ──────────────────────────────────────────────────────

class _RoleMasterList extends ConsumerWidget {
  const _RoleMasterList({
    required this.roles,
    required this.selectedRoleId,
    required this.onSelect,
    required this.onNew,
  });

  final List<TenantRole> roles;
  final String? selectedRoleId;
  final void Function(String roleId) onSelect;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assignmentsAsync = ref.watch(activeRoleAssignmentsProvider);
    final counts = <String, int>{};
    for (final a in assignmentsAsync.value ?? const <RoleAssignment>[]) {
      counts[a.roleId] = (counts[a.roleId] ?? 0) + 1;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                'Perfis (${roles.length})',
                style: VeraProbTypography.kpiLabel,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Spacer(),
            Tooltip(
              message: 'Novo Perfil de Acesso',
              child: FilledButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Novo'),
                onPressed: onNew,
              ),
            ),
          ],
        ),
        const SizedBox(height: VeraProbSpacing.sm),
        Expanded(
          child: roles.isEmpty
              ? const Center(
                  child: Text(
                    'Nenhum perfil personalizado ainda.',
                    style: TextStyle(color: VeraProbColors.textSecondary),
                  ),
                )
              : ListView.separated(
                  itemCount: roles.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final role = roles[i];
                    return _RoleCard(
                      role: role,
                      userCount: counts[role.id] ?? 0,
                      selected: role.id == selectedRoleId,
                      onTap: () => onSelect(role.id),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.role,
    required this.userCount,
    required this.selected,
    required this.onTap,
  });

  final TenantRole role;
  final int userCount;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? VeraProbColors.primary.withValues(alpha: 0.12)
          : VeraProbColors.surface,
      borderRadius: VeraProbRadii.mdAll,
      child: InkWell(
        borderRadius: VeraProbRadii.mdAll,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      role.name,
                      style: VeraProbTypography.dataValue,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (role.isSystem) ...[
                    const SizedBox(width: 8),
                    const _SystemBadge(),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '$userCount usuário(s) · ${role.permissionKeys.length} permissão(ões)',
                style: VeraProbTypography.caption.copyWith(
                  color: VeraProbColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SystemBadge extends StatelessWidget {
  const _SystemBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: VeraProbColors.border,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'SISTEMA',
        style: VeraProbTypography.badge.copyWith(
          color: VeraProbColors.textSecondary,
        ),
      ),
    );
  }
}

// ── Detail: per-module permission matrix editor ──────────────────────────────

class _RoleMatrixEditor extends ConsumerStatefulWidget {
  const _RoleMatrixEditor({
    super.key,
    required this.role,
    required this.dictionary,
    required this.onSaved,
  });

  /// `null` = creating a new role.
  final TenantRole? role;
  final List<TenantPermission> dictionary;
  final VoidCallback onSaved;

  @override
  ConsumerState<_RoleMatrixEditor> createState() => _RoleMatrixEditorState();
}

class _RoleMatrixEditorState extends ConsumerState<_RoleMatrixEditor> {
  late final TextEditingController _nameController;
  // key -> allowlisted contract IDs (empty = unrestricted). Key present = granted.
  late final Map<String, Set<String>> _selection;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.role?.name ?? '');
    _selection = <String, Set<String>>{
      for (final g in widget.role?.grants ?? const <RolePermissionGrant>[])
        g.permissionKey: {...g.contractScopeIds},
    };
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  bool get _isSystem => widget.role?.isSystem ?? false;

  void _toggle(String key, bool value) {
    setState(() {
      if (value) {
        _selection[key] = <String>{};
      } else {
        _selection.remove(key);
      }
    });
  }

  void _toggleScopeContract(String key, String contractId, bool value) {
    setState(() {
      final ids = _selection[key] ?? <String>{};
      if (value) {
        ids.add(contractId);
      } else {
        ids.remove(contractId);
      }
      _selection[key] = ids;
    });
  }

  bool get _touchesSensitive => widget.dictionary.any(
    (p) => p.isSensitive && _selection.containsKey(p.key),
  );

  @override
  Widget build(BuildContext context) {
    // Watched to rebuild on auth/permission change; tiles read it inline so no
    // domain type leaks into a method signature (INV-7 / INV-13 convention).
    ref.watch(permissionServiceProvider);
    final byModule = <String, List<TenantPermission>>{};
    for (final p in widget.dictionary) {
      byModule.putIfAbsent(p.module, () => <TenantPermission>[]).add(p);
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          if (_touchesSensitive) ...[
            const SizedBox(height: 8),
            const _SensitiveBanner(),
          ],
          const SizedBox(height: VeraProbSpacing.sm),
          Expanded(
            child: ListView(
              children: [
                for (final entry in byModule.entries)
                  _buildModuleGroup(entry.key, entry.value),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomActions(),
    );
  }

  Widget _buildHeader() {
    if (widget.role == null) {
      return TextField(
        controller: _nameController,
        decoration: const InputDecoration(
          labelText: 'Nome do Perfil',
          hintText: 'Ex.: Operador Logístico',
        ),
      );
    }
    return Text(
      widget.role!.name,
      style: VeraProbTypography.sectionTitle,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildBottomActions() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(
          top: VeraProbSpacing.md,
          bottom: VeraProbSpacing.sm,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FilledButton.icon(
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: VeraProbColors.background,
                      ),
                    )
                  : const Icon(Icons.save_outlined, size: 18),
              label: const Text('Salvar'),
              onPressed: (_saving || _isSystem) ? null : _save,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModuleGroup(String module, List<TenantPermission> perms) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Text(
            _moduleLabel(module).toUpperCase(),
            style: VeraProbTypography.caption.copyWith(
              color: VeraProbColors.textSecondary,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
        ),
        const Divider(height: 8, color: VeraProbColors.border),
        for (final perm in perms) _buildPermissionTile(perm),
      ],
    );
  }

  Widget _buildPermissionLabel(TenantPermission perm) {
    final label = Text(
      perm.labelPt,
      style: VeraProbTypography.bodyMedium.copyWith(
        color: perm.isSensitive
            ? VeraProbColors.warning
            : VeraProbColors.textPrimary,
      ),
      overflow: TextOverflow.ellipsis,
    );
    if (perm.description.isEmpty) return label;
    return Tooltip(message: perm.description, child: label);
  }

  Widget _buildPermissionTile(TenantPermission perm) {
    final selected = _selection.containsKey(perm.key);
    // Subset-guard preview: an admin cannot grant a permission they lack.
    // Wildcard (TENANT_ADMIN) holds everything, so nothing is disabled for them.
    // ponytail: a pre-existing unheld grant stays checked+disabled; the RPC is
    // the real boundary and maps such a save to a domain error.
    final locked =
        _isSystem ||
        !ref.read(permissionServiceProvider).hasPermission(perm.key);

    return Column(
      children: [
        CheckboxListTile(
          value: selected,
          onChanged: locked ? null : (v) => _toggle(perm.key, v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          title: Row(
            children: [
              Flexible(child: _buildPermissionLabel(perm)),
              if (perm.isSensitive) ...[
                const SizedBox(width: 6),
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 16,
                  color: VeraProbColors.warning,
                ),
              ],
            ],
          ),
          subtitle: perm.description.isEmpty
              ? null
              : Text(perm.description, style: VeraProbTypography.caption),
        ),
        if (selected && perm.isScopable)
          _ScopePicker(
            selectedContractIds: _selection[perm.key] ?? const <String>{},
            onToggle: (id, v) => _toggleScopeContract(perm.key, id, v),
          ),
      ],
    );
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final name = _nameController.text.trim();
    if (widget.role == null && name.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Informe um nome para o perfil.')),
      );
      return;
    }
    setState(() => _saving = true);

    final grants = <RolePermissionGrant>[
      for (final entry in _selection.entries)
        RolePermissionGrant(
          permissionKey: entry.key,
          contractScopeIds: entry.value,
        ),
    ];
    final needsApproval = _touchesSensitive;
    final service = ref.read(accessManagementServiceProvider);

    try {
      if (widget.role == null) {
        await service.createRole(name: name, grants: grants);
      } else {
        await service.updateRolePermissions(
          roleId: widget.role!.id,
          grants: grants,
        );
      }
      ref.invalidate(tenantRolesProvider);
      ref.invalidate(pendingRoleChangesProvider);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            needsApproval
                ? 'Alterações enviadas para aprovação de um segundo administrador.'
                : 'Perfil salvo com sucesso.',
          ),
          backgroundColor: VeraProbColors.success,
        ),
      );
      widget.onSaved();
    } catch (_) {
      if (mounted) setState(() => _saving = false);
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Não foi possível salvar o perfil. Verifique suas permissões e tente novamente.',
          ),
          backgroundColor: VeraProbColors.error,
        ),
      );
    }
  }
}

class _SensitiveBanner extends StatelessWidget {
  const _SensitiveBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: VeraProbColors.warning.withValues(alpha: 0.12),
        borderRadius: VeraProbRadii.smAll,
        border: Border.all(
          color: VeraProbColors.warning.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.shield_outlined,
            size: 18,
            color: VeraProbColors.warning,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Este perfil inclui permissões sensíveis: a alteração exige aprovação de um segundo administrador.',
              style: VeraProbTypography.caption.copyWith(
                color: VeraProbColors.warning,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Optional resource allowlist (ABAC-lite) for a scopable permission. No
/// selection = unrestricted within the tenant.
class _ScopePicker extends ConsumerWidget {
  const _ScopePicker({
    required this.selectedContractIds,
    required this.onToggle,
  });

  final Set<String> selectedContractIds;
  final void Function(String contractId, bool value) onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contractsAsync = ref.watch(contractListProvider);
    final label = selectedContractIds.isEmpty
        ? 'Sem restrição (todo o tenant)'
        : '${selectedContractIds.length} contrato(s) selecionado(s)';

    return Padding(
      padding: const EdgeInsets.only(left: 32, bottom: 8),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text(
            'Restringir a recursos — $label',
            style: VeraProbTypography.caption.copyWith(
              color: VeraProbColors.primary,
            ),
          ),
          children: [
            switch (contractsAsync) {
              AsyncData(:final value) => Column(
                children: [
                  for (final c in value)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: selectedContractIds.contains(c.id),
                      onChanged: (v) => onToggle(c.id, v ?? false),
                      title: Text(
                        c.name,
                        style: VeraProbTypography.caption,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
              AsyncError() => const Text(
                'Não foi possível carregar os contratos.',
                style: TextStyle(color: VeraProbColors.error, fontSize: 12),
              ),
              _ => const Padding(
                padding: EdgeInsets.all(8),
                child: LinearProgressIndicator(),
              ),
            },
          ],
        ),
      ),
    );
  }
}

// ── Four-eyes approval queue ─────────────────────────────────────────────────

class _PendingApprovalsSection extends ConsumerWidget {
  const _PendingApprovalsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingAsync = ref.watch(pendingRoleChangesProvider);
    final requests = pendingAsync.value ?? const <RoleChangeRequest>[];
    if (requests.isEmpty) return const SizedBox.shrink();

    final currentUserId = ref.watch(currentOperatorIdProvider);
    final roles = ref.watch(tenantRolesProvider).value ?? const <TenantRole>[];
    final rolesById = <String, TenantRole>{for (final r in roles) r.id: r};
    final labelByKey = <String, String>{
      for (final p
          in ref.watch(permissionDictionaryProvider).value ??
              const <TenantPermission>[])
        p.key: p.labelPt,
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: VeraProbColors.surface,
        borderRadius: VeraProbRadii.mdAll,
        border: Border.all(color: VeraProbColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.how_to_reg_outlined,
                size: 18,
                color: VeraProbColors.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Aprovações Pendentes (${requests.length})',
                style: VeraProbTypography.kpiLabel,
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final req in requests)
            _ApprovalRow(
              request: req,
              isOwnRequest: req.requestedBy == currentUserId,
              targetRole: req.roleId == null ? null : rolesById[req.roleId],
              labelByKey: labelByKey,
            ),
        ],
      ),
    );
  }
}

class _ApprovalRow extends ConsumerStatefulWidget {
  const _ApprovalRow({
    required this.request,
    required this.isOwnRequest,
    required this.targetRole,
    required this.labelByKey,
  });

  final RoleChangeRequest request;
  final bool isOwnRequest;

  /// Resolved role for UPDATE_ROLE_PERMISSIONS/GRANT_ROLE payloads (`null` for
  /// CREATE_ROLE or when the role vanished from the catalog).
  final TenantRole? targetRole;
  final Map<String, String> labelByKey;

  @override
  ConsumerState<_ApprovalRow> createState() => _ApprovalRowState();
}

class _ApprovalRowState extends ConsumerState<_ApprovalRow> {
  bool _busy = false;

  Future<void> _decide({required bool approve}) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    final service = ref.read(accessManagementServiceProvider);
    try {
      if (approve) {
        await service.approveRequest(widget.request.id);
      } else {
        await service.rejectRequest(widget.request.id);
      }
      ref.invalidate(pendingRoleChangesProvider);
      ref.invalidate(tenantRolesProvider);
      ref.invalidate(activeRoleAssignmentsProvider);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            approve ? 'Solicitação aprovada.' : 'Solicitação rejeitada.',
          ),
          backgroundColor: VeraProbColors.success,
        ),
      );
    } catch (_) {
      if (mounted) setState(() => _busy = false);
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Não foi possível concluir a decisão. Tente novamente.',
          ),
          backgroundColor: VeraProbColors.error,
        ),
      );
    }
  }

  /// Diff against the role's current grants. CREATE_ROLE has no current set
  /// (everything is an addition); GRANT_ROLE carries no permission keys.
  ({Set<String> added, Set<String> removed}) get _diff {
    final req = widget.request;
    if (req.requestType == 'GRANT_ROLE') {
      return (added: const <String>{}, removed: const <String>{});
    }
    final proposed = req.proposedPermissionKeys.toSet();
    final current = req.requestType == 'UPDATE_ROLE_PERMISSIONS'
        ? (widget.targetRole?.permissionKeys ?? const <String>{})
        : const <String>{};
    return (
      added: proposed.difference(current),
      removed: current.difference(proposed),
    );
  }

  String get _title {
    final req = widget.request;
    final roleName = req.requestType == 'CREATE_ROLE'
        ? req.proposedRoleName
        : widget.targetRole?.name;
    final label = _requestTypeLabel(req.requestType);
    return roleName == null || roleName.isEmpty ? label : '$label · $roleName';
  }

  @override
  Widget build(BuildContext context) {
    final diff = _diff;
    final requestedAt = DateFormat(
      'dd/MM/yyyy',
    ).format(widget.request.createdAtUtc.toLocal());

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _buildTitle(requestedAt)),
              _buildTrailing(),
            ],
          ),
          if (diff.added.isNotEmpty || diff.removed.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final key in diff.added)
                    _DiffChip(
                      label: widget.labelByKey[key] ?? key,
                      added: true,
                    ),
                  for (final key in diff.removed)
                    _DiffChip(
                      label: widget.labelByKey[key] ?? key,
                      added: false,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTitle(String requestedAt) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _title,
          style: VeraProbTypography.caption.copyWith(
            color: VeraProbColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          'Solicitado em $requestedAt',
          style: VeraProbTypography.caption.copyWith(
            color: VeraProbColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildTrailing() {
    if (widget.isOwnRequest) {
      return Text(
        'Aguardando outro administrador',
        style: VeraProbTypography.caption.copyWith(
          color: VeraProbColors.textSecondary,
          fontStyle: FontStyle.italic,
        ),
      );
    }
    if (_busy) {
      return const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          onPressed: () => _decide(approve: false),
          style: TextButton.styleFrom(foregroundColor: VeraProbColors.error),
          child: const Text('Rejeitar'),
        ),
        const SizedBox(width: 4),
        FilledButton(
          onPressed: () => _decide(approve: true),
          child: const Text('Aprovar'),
        ),
      ],
    );
  }
}

/// One permission in a four-eyes diff: Emerald tint for additions, Red tint
/// for removals. Tinted surfaces keep the semantic color as foreground text
/// (never an accent fill — ACCENT-FILL-CONTRAST does not apply to tints).
class _DiffChip extends StatelessWidget {
  const _DiffChip({required this.label, required this.added});

  final String label;
  final bool added;

  @override
  Widget build(BuildContext context) {
    final color = added ? VeraProbColors.success : VeraProbColors.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        '${added ? '+' : '−'} $label',
        style: VeraProbTypography.caption.copyWith(color: color),
      ),
    );
  }
}

String _requestTypeLabel(String type) => switch (type) {
  'CREATE_ROLE' => 'Novo perfil',
  'UPDATE_ROLE_PERMISSIONS' => 'Atualizar permissões',
  'GRANT_ROLE' => 'Atribuir perfil',
  _ => type,
};

String _moduleLabel(String module) => switch (module) {
  'financial' => 'Financeiro',
  'sla' => 'SLA & Sanções',
  'contracts' => 'Contratos',
  'telemetry' => 'Telemetria',
  'cadastros' => 'Cadastros',
  'roles' => 'Governança',
  _ => module,
};

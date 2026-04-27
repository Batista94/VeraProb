import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/application/admin/org_capabilities.dart';
import 'package:veraprob/state/providers/admin_providers.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/application/admin/update_org_settings_command.dart';

/// Screen for editing organization-wide settings.
class OrgSettingsScreen extends ConsumerStatefulWidget {
  const OrgSettingsScreen({super.key});

  @override
  ConsumerState<OrgSettingsScreen> createState() => _OrgSettingsScreenState();
}

class _OrgSettingsScreenState extends ConsumerState<OrgSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _timezoneController = TextEditingController();
  final _currencyController = TextEditingController();
  final _logoUrlController = TextEditingController();
  final _orgTypeController = TextEditingController();

  OrgCapabilities _capabilities = OrgCapabilities.defaults;
  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _timezoneController.dispose();
    _currencyController.dispose();
    _logoUrlController.dispose();
    _orgTypeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final orgAsync = ref.watch(orgSettingsProvider);
    final userRole = ref.watch(currentUserRoleProvider);
    final isSuperAdmin = userRole == UserRole.superAdmin;

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
                  Icons.business_outlined,
                  size: 28,
                  color: VeraProbColors.primary,
                ),
                const SizedBox(width: 12),
                Text(
                  'Configurações da Organização',
                  style: VeraProbTypography.sectionTitle,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Gerencie o perfil público, fuso horário e moeda padrão da sua empresa.',
              style: VeraProbTypography.bodyMedium.copyWith(
                color: VeraProbColors.textSecondary,
              ),
            ),
            const SizedBox(height: 32),
            Expanded(
              child: orgAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Text(
                    'Erro ao carregar configurações: $e',
                    style: const TextStyle(color: VeraProbColors.error),
                  ),
                ),
                data: (org) {
                  if (org == null) {
                    return const Center(
                      child: Text('Organização não encontrada'),
                    );
                  }

                  // Initialize controllers once
                  if (_nameController.text.isEmpty && !_isSaving) {
                    _nameController.text = org.name;
                    _timezoneController.text = org.timezone;
                    _currencyController.text = org.currencyCode;
                    _logoUrlController.text = org.logoUrl ?? '';
                    _orgTypeController.text = org.organizationType ?? '';
                    _capabilities = org.capabilities;
                  }

                  return Form(
                    key: _formKey,
                    child: SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 600),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextFormField(
                              controller: _nameController,
                              readOnly: !isSuperAdmin,
                              decoration: InputDecoration(
                                labelText: 'Nome da Organização',
                                prefixIcon: Icon(
                                  isSuperAdmin
                                      ? Icons.edit_outlined
                                      : Icons.lock_outline,
                                  size: 20,
                                ),
                                helperText: isSuperAdmin
                                    ? 'Atualização permitida para Super Admin.'
                                    : 'Campos estruturais bloqueados por contrato. Contate o suporte para alterações.',
                              ),
                            ),
                            const SizedBox(height: 24),
                            TextFormField(
                              controller: _timezoneController,
                              readOnly: !isSuperAdmin,
                              decoration: InputDecoration(
                                labelText: 'Fuso Horário',
                                prefixIcon: Icon(
                                  isSuperAdmin
                                      ? Icons.access_time
                                      : Icons.lock_outline,
                                  size: 20,
                                ),
                                helperText: isSuperAdmin
                                    ? 'Atualização permitida para Super Admin.'
                                    : 'Campos estruturais bloqueados por contrato. Contate o suporte para alterações.',
                              ),
                            ),
                            const SizedBox(height: 24),
                            TextFormField(
                              controller: _currencyController,
                              readOnly: !isSuperAdmin,
                              decoration: InputDecoration(
                                labelText: 'Código da Moeda',
                                prefixIcon: Icon(
                                  isSuperAdmin
                                      ? Icons.monetization_on_outlined
                                      : Icons.lock_outline,
                                  size: 20,
                                ),
                                helperText: isSuperAdmin
                                    ? 'Atualização permitida para Super Admin.'
                                    : 'Campos estruturais bloqueados por contrato. Contate o suporte para alterações.',
                              ),
                            ),
                            const SizedBox(height: 24),
                            TextFormField(
                              controller: _logoUrlController,
                              decoration: const InputDecoration(
                                labelText: 'URL do Logotipo',
                                helperText:
                                    'Link para imagem SVG ou PNG da marca.',
                              ),
                            ),
                            const SizedBox(height: 24),
                            TextFormField(
                              controller: _orgTypeController,
                              decoration: const InputDecoration(
                                labelText: 'Tipo de Operação (cosmético)',
                                prefixIcon: Icon(Icons.label_outline, size: 20),
                                helperText:
                                    'Rótulo visual. Ex: CARGO, PASSENGER, URBAN_LOGISTICS. Não afeta regras do motor.',
                              ),
                            ),
                            const SizedBox(height: 32),
                            // ── Capacidades Operacionais (Phase 10 — INV-14) ──
                            Row(
                              children: [
                                const Icon(
                                  Icons.tune_outlined,
                                  size: 18,
                                  color: VeraProbColors.primary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Capacidades Operacionais',
                                  style: VeraProbTypography.sectionTitle
                                      .copyWith(fontSize: 14),
                                ),
                              ],
                            ),
                            Text(
                              'Controla quais categorias de evidência aparecem no bot Telegram para motoristas desta organização.',
                              style: VeraProbTypography.bodyMedium.copyWith(
                                color: VeraProbColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _CapabilityTile(
                              title: 'Lacre & Checklist Saída',
                              subtitle:
                                  'Categorias: lacre, chk_saida. Auto-inicia trânsito.',
                              value: _capabilities.allowsSealing,
                              onChanged: (v) => setState(
                                () => _capabilities = _capabilities.copyWith(
                                  allowsSealing: v,
                                ),
                              ),
                            ),
                            _CapabilityTile(
                              title: 'Carregamento',
                              subtitle:
                                  'Categoria: carregamento. Auto-inicia trânsito.',
                              value: _capabilities.allowsLoading,
                              onChanged: (v) => setState(
                                () => _capabilities = _capabilities.copyWith(
                                  allowsLoading: v,
                                ),
                              ),
                            ),
                            _CapabilityTile(
                              title: 'Incidente / SLA',
                              subtitle: 'Categoria: incidente.',
                              value: _capabilities.allowsIncident,
                              onChanged: (v) => setState(
                                () => _capabilities = _capabilities.copyWith(
                                  allowsIncident: v,
                                ),
                              ),
                            ),
                            _CapabilityTile(
                              title: 'Documental / NF',
                              subtitle: 'Categoria: doc.',
                              value: _capabilities.allowsDoc,
                              onChanged: (v) => setState(
                                () => _capabilities = _capabilities.copyWith(
                                  allowsDoc: v,
                                ),
                              ),
                            ),
                            _CapabilityTile(
                              title: 'Auto-Classificação por GPS',
                              subtitle:
                                  'Classifica foto automaticamente pelo EXIF GPS vs. zonas operacionais.',
                              value: _capabilities.smartClassify,
                              onChanged: (v) => setState(
                                () => _capabilities = _capabilities.copyWith(
                                  smartClassify: v,
                                ),
                              ),
                            ),
                            const SizedBox(height: 32),
                            SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: FilledButton.icon(
                                icon: _isSaving
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.save_outlined),
                                label: const Text('Salvar Alterações'),
                                onPressed: _isSaving ? null : _save,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSaving = true);
    try {
      final orgId = ref.read(currentOrganizationIdProvider);
      final role = ref.read(currentUserRoleProvider);
      final sessionId = ref.read(currentSessionIdProvider) ?? '';

      final command = UpdateOrgSettingsCommand(
        organizationId: orgId!,
        callerRole: role,
        name: role == UserRole.superAdmin ? _nameController.text.trim() : null,
        timezone: role == UserRole.superAdmin
            ? _timezoneController.text.trim()
            : null,
        currencyCode: role == UserRole.superAdmin
            ? _currencyController.text.trim()
            : null,
        logoUrl: _logoUrlController.text.trim().isEmpty
            ? null
            : _logoUrlController.text.trim(),
        organizationType: _orgTypeController.text.trim().isEmpty
            ? null
            : _orgTypeController.text.trim(),
        capabilities: _capabilities,
        sessionId: sessionId,
      );

      await ref.read(updateOrgSettingsHandlerProvider).handle(command);

      ref.invalidate(orgSettingsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Configurações salvas com sucesso!'),
            backgroundColor: VeraProbColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar: $e'),
            backgroundColor: VeraProbColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}

class _CapabilityTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _CapabilityTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(title, style: VeraProbTypography.bodyMedium),
      subtitle: Text(
        subtitle,
        style: VeraProbTypography.bodyMedium.copyWith(
          color: VeraProbColors.textSecondary,
          fontSize: 11,
        ),
      ),
      value: value,
      onChanged: onChanged,
      activeThumbColor: VeraProbColors.primary,
    );
  }
}

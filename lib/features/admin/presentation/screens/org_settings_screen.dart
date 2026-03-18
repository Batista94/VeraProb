import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../state/providers/admin_providers.dart';
import '../../../../state/providers/auth_providers.dart';
import '../../../../application/admin/update_org_settings_command.dart';

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

  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _timezoneController.dispose();
    _currencyController.dispose();
    _logoUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final orgAsync = ref.watch(orgSettingsProvider);

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
                  color: PactaFlowColors.primary,
                ),
                const SizedBox(width: 12),
                Text(
                  'Configurações da Organização',
                  style: PactaFlowTypography.sectionTitle,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Gerencie o perfil público, fuso horário e moeda padrão da sua empresa.',
              style: PactaFlowTypography.bodyMedium.copyWith(
                color: PactaFlowColors.textSecondary,
              ),
            ),
            const SizedBox(height: 32),
            Expanded(
              child: orgAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Text(
                    'Erro ao carregar configurações: $e',
                    style: const TextStyle(color: PactaFlowColors.error),
                  ),
                ),
                data: (org) {
                  if (org == null)
                    return const Center(
                      child: Text('Organização não encontrada'),
                    );

                  // Initialize controllers once
                  if (_nameController.text.isEmpty && !_isSaving) {
                    _nameController.text = org.name;
                    _timezoneController.text = org.timezone;
                    _currencyController.text = org.currencyCode;
                    _logoUrlController.text = org.logoUrl ?? '';
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
                              decoration: const InputDecoration(
                                labelText: 'Nome da Organização',
                                helperText:
                                    'Nome exibido em relatórios e faturas.',
                              ),
                              validator: (v) =>
                                  v?.isEmpty ?? true ? 'Obrigatório' : null,
                            ),
                            const SizedBox(height: 24),
                            TextFormField(
                              controller: _timezoneController,
                              decoration: const InputDecoration(
                                labelText: 'Fuso Horário',
                                helperText:
                                    'Ex: America/Sao_Paulo (usado para cálculos de SLA).',
                              ),
                              validator: (v) =>
                                  v?.isEmpty ?? true ? 'Obrigatório' : null,
                            ),
                            const SizedBox(height: 24),
                            TextFormField(
                              controller: _currencyController,
                              decoration: const InputDecoration(
                                labelText: 'Código da Moeda',
                                helperText:
                                    'Ex: BRL, USD (usado para valores financeiros).',
                              ),
                              validator: (v) =>
                                  v?.isEmpty ?? true ? 'Obrigatório' : null,
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
                            const SizedBox(height: 48),
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

      final command = UpdateOrgSettingsCommand(
        organizationId: orgId!,
        callerRole: role,
        name: _nameController.text.trim(),
        timezone: _timezoneController.text.trim(),
        currencyCode: _currencyController.text.trim(),
        logoUrl: _logoUrlController.text.trim().isEmpty
            ? null
            : _logoUrlController.text.trim(),
      );

      await ref.read(updateOrgSettingsHandlerProvider).handle(command);

      ref.invalidate(orgSettingsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Configurações salvas com sucesso!'),
            backgroundColor: PactaFlowColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar: $e'),
            backgroundColor: PactaFlowColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}

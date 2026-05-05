import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/application/admin/org_capabilities.dart';
import 'package:veraprob/application/admin/update_org_operational_params_command.dart';
import 'package:veraprob/state/providers/admin_providers.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/application/admin/update_org_settings_command.dart';
import 'package:veraprob/presentation/shared/widgets/domain_chip_input.dart';
import 'package:veraprob/state/providers/super_admin_providers.dart';
import 'package:veraprob/state/providers/super_admin_auth_providers.dart';

/// Screen for editing organization-wide settings.
///
/// Split into two sections:
///   1. Configurações Gerais (name, timezone, currency, logo, capabilities)
///   2. Parâmetros Operacionais (dwell_time_seconds, max_kinematic_speed_kmh)
///      — configurações de negócio editáveis pelo Admin da Org.
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
  OrgCapabilities? _originalCapabilities;
  final _capReasonController = TextEditingController();
  bool _isSaving = false;

  // ── Parâmetros Operacionais (editáveis pelo Admin da Org) ──────────────────
  final _opParamsFormKey = GlobalKey<FormState>();
  final _opReasonController = TextEditingController();
  int _dwellTimeSeconds = 300;
  double _maxKinematicSpeedKmh = 80.0; // Physical Metric - Double Required
  bool _opParamsInitialized = false;
  bool _isSavingOpParams = false;

  // ── Domínios Permitidos (SuperAdmin only) ──────────────────────────────────
  List<String> _allowedDomains = [];
  bool _domainsInitialized = false;
  bool _savingDomains = false;

  @override
  void dispose() {
    _nameController.dispose();
    _timezoneController.dispose();
    _currencyController.dispose();
    _logoUrlController.dispose();
    _orgTypeController.dispose();
    _capReasonController.dispose();
    _opReasonController.dispose();
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
              'Gerencie o perfil público, fuso horário, moeda e parâmetros operacionais da sua empresa.',
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
                    _originalCapabilities ??= org.capabilities;
                  }

                  // Initialize operational params once
                  if (!_opParamsInitialized) {
                    _dwellTimeSeconds = org.dwellTimeSeconds;
                    _maxKinematicSpeedKmh =
                        org.capabilities.maxKinematicSpeedKmh ??
                        80.0; // Physical Metric - Double Required
                    _opParamsInitialized = true;
                  }

                  if (!_domainsInitialized) {
                    _allowedDomains = List<String>.from(org.allowedDomains);
                    _domainsInitialized = true;
                  }

                  return SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 600),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── Seção 1: Configurações Gerais ─────────────────
                          Form(
                            key: _formKey,
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
                                    prefixIcon: Icon(
                                      Icons.label_outline,
                                      size: 20,
                                    ),
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
                                    () => _capabilities = _capabilities
                                        .copyWith(allowsSealing: v),
                                  ),
                                ),
                                _CapabilityTile(
                                  title: 'Carregamento',
                                  subtitle:
                                      'Categoria: carregamento. Auto-inicia trânsito.',
                                  value: _capabilities.allowsLoading,
                                  onChanged: (v) => setState(
                                    () => _capabilities = _capabilities
                                        .copyWith(allowsLoading: v),
                                  ),
                                ),
                                _CapabilityTile(
                                  title: 'Incidente / SLA',
                                  subtitle: 'Categoria: incidente.',
                                  value: _capabilities.allowsIncident,
                                  onChanged: (v) => setState(
                                    () => _capabilities = _capabilities
                                        .copyWith(allowsIncident: v),
                                  ),
                                ),
                                _CapabilityTile(
                                  title: 'Documental / NF',
                                  subtitle: 'Categoria: doc.',
                                  value: _capabilities.allowsDoc,
                                  onChanged: (v) => setState(
                                    () => _capabilities = _capabilities
                                        .copyWith(allowsDoc: v),
                                  ),
                                ),
                                _CapabilityTile(
                                  title: 'Auto-Classificação por GPS',
                                  subtitle:
                                      'Classifica foto automaticamente pelo EXIF GPS vs. zonas operacionais.',
                                  value: _capabilities.smartClassify,
                                  onChanged: (v) => setState(
                                    () => _capabilities = _capabilities
                                        .copyWith(smartClassify: v),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _capReasonController,
                                  maxLines: 2,
                                  decoration: const InputDecoration(
                                    labelText:
                                        'Justificativa para mudança de capacidades',
                                    hintText:
                                        'Ex: Desativando lacre por solicitação da área operacional',
                                    helperText:
                                        'Obrigatória apenas quando capacidades forem alteradas (auditoria).',
                                  ),
                                  validator: (v) {
                                    final changed =
                                        _originalCapabilities != null &&
                                        _capabilities != _originalCapabilities;
                                    if (!changed) return null;
                                    if (v == null || v.trim().isEmpty) {
                                      return 'Justificativa obrigatória ao alterar capacidades';
                                    }
                                    if (v.trim().length < 10) {
                                      return 'Mínimo de 10 caracteres';
                                    }
                                    return null;
                                  },
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

                          // ── Seção 2: Parâmetros Operacionais ──────────────
                          const SizedBox(height: 40),
                          const Divider(),
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              const Icon(
                                Icons.speed_outlined,
                                size: 18,
                                color: VeraProbColors.primary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Parâmetros Operacionais',
                                style: VeraProbTypography.sectionTitle.copyWith(
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Configurações de negócio editáveis pelo Admin da Organização. '
                            'Estas são configurações operacionais — não financeiras.',
                            style: VeraProbTypography.bodyMedium.copyWith(
                              color: VeraProbColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Form(
                            key: _opParamsFormKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Dwell time slider
                                Text(
                                  'Tempo de Parada (Fechamento Automático)',
                                  style: VeraProbTypography.bodyMedium.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${_dwellTimeSeconds}s (~${(_dwellTimeSeconds / 60).round()} min) '
                                  '— tempo sem movimento para fechar parada automaticamente.',
                                  style: VeraProbTypography.bodyMedium.copyWith(
                                    color: VeraProbColors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                                SliderTheme(
                                  data: const SliderThemeData(
                                    thumbShape: RoundSliderThumbShape(
                                      enabledThumbRadius: 6,
                                    ),
                                    overlayShape: RoundSliderOverlayShape(
                                      overlayRadius: 14,
                                    ),
                                    trackHeight: 2,
                                    activeTrackColor: VeraProbColors.primary,
                                    inactiveTrackColor: VeraProbColors.border,
                                    thumbColor: VeraProbColors.primary,
                                  ),
                                  child: Slider(
                                    value: _dwellTimeSeconds.toDouble(),
                                    min: 60,
                                    max: 1800,
                                    divisions: 29,
                                    label: '${_dwellTimeSeconds}s',
                                    onChanged: (v) => setState(
                                      () => _dwellTimeSeconds = v.round(),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 20),

                                // Speed slider
                                Text(
                                  'Velocidade Máxima para Alerta (km/h)',
                                  style: VeraProbTypography.bodyMedium.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${_maxKinematicSpeedKmh.toStringAsFixed(0)} km/h '
                                  '— velocidade acima desta marca gera alerta no monitor.',
                                  style: VeraProbTypography.bodyMedium.copyWith(
                                    color: VeraProbColors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                                SliderTheme(
                                  data: const SliderThemeData(
                                    thumbShape: RoundSliderThumbShape(
                                      enabledThumbRadius: 6,
                                    ),
                                    overlayShape: RoundSliderOverlayShape(
                                      overlayRadius: 14,
                                    ),
                                    trackHeight: 2,
                                    activeTrackColor: VeraProbColors.primary,
                                    inactiveTrackColor: VeraProbColors.border,
                                    thumbColor: VeraProbColors.primary,
                                  ),
                                  child: Slider(
                                    value: _maxKinematicSpeedKmh.clamp(
                                      10.0,
                                      200.0,
                                    ), // Physical Metric - Double Required
                                    min: 10,
                                    max: 200,
                                    divisions: 38,
                                    label:
                                        '${_maxKinematicSpeedKmh.toStringAsFixed(0)} km/h',
                                    onChanged: (v) => setState(
                                      () => _maxKinematicSpeedKmh =
                                          v, // Physical Metric - Double Required
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 20),

                                // Reason (mandatory for operational changes)
                                Text(
                                  'Justificativa *',
                                  style: VeraProbTypography.bodyMedium.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Obrigatória para mudanças de parâmetros operacionais (auditoria).',
                                  style: VeraProbTypography.bodyMedium.copyWith(
                                    color: VeraProbColors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextFormField(
                                  controller: _opReasonController,
                                  maxLines: 2,
                                  decoration: const InputDecoration(
                                    hintText:
                                        'Ex: Ajuste de velocidade após mudança de rota pela empresa X',
                                  ),
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) {
                                      return 'Justificativa é obrigatória';
                                    }
                                    if (v.trim().length < 10) {
                                      return 'Mínimo de 10 caracteres';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 20),
                                SizedBox(
                                  width: double.infinity,
                                  height: 48,
                                  child: OutlinedButton.icon(
                                    icon: _isSavingOpParams
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(Icons.tune_outlined),
                                    label: const Text(
                                      'Salvar Parâmetros Operacionais',
                                    ),
                                    onPressed: _isSavingOpParams
                                        ? null
                                        : _saveOpParams,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isSuperAdmin) ...[
                            const SizedBox(height: VeraProbSpacing.lg),
                            const Divider(color: VeraProbColors.border),
                            const SizedBox(height: VeraProbSpacing.md),
                            Row(
                              children: [
                                const Icon(
                                  Icons.security_outlined,
                                  size: 20,
                                  color: VeraProbColors.primary,
                                ),
                                const SizedBox(width: VeraProbSpacing.sm),
                                Text(
                                  'Domínios Permitidos',
                                  style: VeraProbTypography.sectionTitle,
                                ),
                              ],
                            ),
                            const SizedBox(height: VeraProbSpacing.xs),
                            Text(
                              'Acesso restrito a e-mails destes domínios (SSO e prevenção de identity injection).',
                              style: VeraProbTypography.bodySmall,
                            ),
                            const SizedBox(height: VeraProbSpacing.sm),
                            DomainChipInput(
                              initialDomains: _allowedDomains,
                              onChanged: (domains) =>
                                  setState(() => _allowedDomains = domains),
                              hintText: 'ex: empresa.com.br',
                            ),
                            const SizedBox(height: VeraProbSpacing.md),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: FilledButton.icon(
                                icon: _savingDomains
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.save_outlined),
                                label: const Text('Salvar Domínios'),
                                onPressed: _savingDomains
                                    ? null
                                    : _saveAllowedDomains,
                              ),
                            ),
                            const SizedBox(height: VeraProbSpacing.md),
                          ],
                        ],
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

      final capabilitiesChanged =
          _originalCapabilities != null &&
          _capabilities != _originalCapabilities;

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
        capabilities: capabilitiesChanged ? _capabilities : null,
        reason: capabilitiesChanged ? _capReasonController.text.trim() : null,
        sessionId: sessionId,
      );

      await ref.read(updateOrgSettingsHandlerProvider).handle(command);

      if (capabilitiesChanged) {
        _originalCapabilities = _capabilities;
        _capReasonController.clear();
      }
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

  Future<void> _saveOpParams() async {
    if (!(_opParamsFormKey.currentState?.validate() ?? false)) return;

    setState(() => _isSavingOpParams = true);
    try {
      final orgId = ref.read(currentOrganizationIdProvider);
      final role = ref.read(currentUserRoleProvider);
      final sessionId = ref.read(currentSessionIdProvider) ?? '';

      final command = UpdateOrgOperationalParamsCommand(
        organizationId: orgId!,
        callerRole: role,
        dwellTimeSeconds: _dwellTimeSeconds,
        maxKinematicSpeedKmh:
            _maxKinematicSpeedKmh, // Physical Metric - Double Required
        reason: _opReasonController.text.trim(),
        sessionId: sessionId,
      );

      await ref.read(updateOrgOperationalParamsHandlerProvider).handle(command);

      _opReasonController.clear();
      ref.invalidate(orgSettingsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Parâmetros operacionais atualizados!'),
            backgroundColor: VeraProbColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar parâmetros: $e'),
            backgroundColor: VeraProbColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingOpParams = false);
    }
  }

  Future<void> _saveAllowedDomains() async {
    setState(() => _savingDomains = true);
    try {
      final orgId = ref.read(currentOrganizationIdProvider);
      final superAdminId = ref.read(currentSuperAdminIdProvider);
      if (orgId == null || superAdminId == null) return;

      await ref
          .read(superAdminRepositoryProvider)
          .updateAllowedDomains(orgId, _allowedDomains, superAdminId);

      ref.invalidate(orgSettingsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Domínios atualizados com sucesso!'),
            backgroundColor: VeraProbColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar domínios: $e'),
            backgroundColor: VeraProbColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _savingDomains = false);
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

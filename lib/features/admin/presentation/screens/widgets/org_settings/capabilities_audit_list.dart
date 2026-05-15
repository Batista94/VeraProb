import 'package:flutter/material.dart';

import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/application/admin/org_capabilities.dart';

/// Capacidades Operacionais (Phase 10 — INV-14): evidence-category toggles
/// plus the mandatory audit justification field.
///
/// Stateless — the parent `_OrgSettingsScreenState` owns `_capabilities` and
/// the reason controller; mutations are surfaced via [onCapabilitiesChanged].
class CapabilitiesAuditList extends StatelessWidget {
  const CapabilitiesAuditList({
    super.key,
    required this.capabilities,
    required this.originalCapabilities,
    required this.capReasonController,
    required this.onCapabilitiesChanged,
  });

  final OrgCapabilities capabilities;
  final OrgCapabilities? originalCapabilities;
  final TextEditingController capReasonController;
  final ValueChanged<OrgCapabilities> onCapabilitiesChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
              style: VeraProbTypography.sectionTitle.copyWith(fontSize: 14),
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
          subtitle: 'Categorias: lacre, chk_saida. Auto-inicia trânsito.',
          value: capabilities.allowsSealing,
          onChanged: (v) =>
              onCapabilitiesChanged(capabilities.copyWith(allowsSealing: v)),
        ),
        _CapabilityTile(
          title: 'Carregamento',
          subtitle: 'Categoria: carregamento. Auto-inicia trânsito.',
          value: capabilities.allowsLoading,
          onChanged: (v) =>
              onCapabilitiesChanged(capabilities.copyWith(allowsLoading: v)),
        ),
        _CapabilityTile(
          title: 'Incidente / SLA',
          subtitle: 'Categoria: incidente.',
          value: capabilities.allowsIncident,
          onChanged: (v) =>
              onCapabilitiesChanged(capabilities.copyWith(allowsIncident: v)),
        ),
        _CapabilityTile(
          title: 'Documental / NF',
          subtitle: 'Categoria: doc.',
          value: capabilities.allowsDoc,
          onChanged: (v) =>
              onCapabilitiesChanged(capabilities.copyWith(allowsDoc: v)),
        ),
        _CapabilityTile(
          title: 'Auto-Classificação por GPS',
          subtitle:
              'Classifica foto automaticamente pelo EXIF GPS vs. zonas operacionais.',
          value: capabilities.smartClassify,
          onChanged: (v) =>
              onCapabilitiesChanged(capabilities.copyWith(smartClassify: v)),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: capReasonController,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Justificativa para mudança de capacidades',
            hintText:
                'Ex: Desativando lacre por solicitação da área operacional',
            helperText:
                'Obrigatória apenas quando capacidades forem alteradas (auditoria).',
          ),
          validator: (v) {
            final changed =
                originalCapabilities != null &&
                capabilities != originalCapabilities;
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
      ],
    );
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

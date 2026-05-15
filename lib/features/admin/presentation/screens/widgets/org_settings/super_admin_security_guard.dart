import 'package:flutter/material.dart';

import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/presentation/shared/ui/domain_chip_input.dart';

/// Seção 3 das Configurações da Organização: domínios de e-mail permitidos
/// (SuperAdmin only — SSO / prevenção de identity injection).
///
/// Stateless — o parent `_OrgSettingsScreenState` é dono de `_allowedDomains`
/// e do handler de salvamento. Renderiza nada para callers não-SuperAdmin.
class SuperAdminSecurityGuard extends StatelessWidget {
  const SuperAdminSecurityGuard({
    super.key,
    required this.isSuperAdmin,
    required this.allowedDomains,
    required this.savingDomains,
    required this.onDomainsChanged,
    required this.onSave,
  });

  final bool isSuperAdmin;
  final List<String> allowedDomains;
  final bool savingDomains;
  final ValueChanged<List<String>> onDomainsChanged;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    if (!isSuperAdmin) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
            Text('Domínios Permitidos', style: VeraProbTypography.sectionTitle),
          ],
        ),
        const SizedBox(height: VeraProbSpacing.xs),
        Text(
          'Acesso restrito a e-mails destes domínios (SSO e prevenção de identity injection).',
          style: VeraProbTypography.bodySmall,
        ),
        const SizedBox(height: VeraProbSpacing.sm),
        DomainChipInput(
          initialDomains: allowedDomains,
          onChanged: onDomainsChanged,
          hintText: 'ex: empresa.com.br',
        ),
        const SizedBox(height: VeraProbSpacing.md),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            icon: savingDomains
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: const Text('Salvar Domínios'),
            onPressed: savingDomains ? null : onSave,
          ),
        ),
        const SizedBox(height: VeraProbSpacing.md),
      ],
    );
  }
}

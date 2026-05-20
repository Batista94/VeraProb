import 'package:flutter/material.dart';
import 'package:veraprob/application/super_admin/tenant_health_view.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/features/super_admin/presentation/widgets/org_secret_card.dart';

class TenantSecurityTab extends StatelessWidget {
  final TenantHealthView tenant;
  const TenantSecurityTab({super.key, required this.tenant});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OrgSecretCard(
            organizationId: tenant.id,
            organizationName: tenant.name,
          ),
          const SizedBox(height: 16),
          // Domínios permitidos foram movidos para a aba Configuração (CT10).
          const Text(
            'Para gerenciar domínios de e-mail permitidos, acesse a aba Configuração.',
            style: TextStyle(
              fontSize: 12,
              color: VeraProbColors.textSecondary,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

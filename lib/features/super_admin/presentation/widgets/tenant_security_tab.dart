import 'package:flutter/material.dart';
import 'package:veraprob/features/super_admin/application/tenant_health_view.dart';
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
        ],
      ),
    );
  }
}

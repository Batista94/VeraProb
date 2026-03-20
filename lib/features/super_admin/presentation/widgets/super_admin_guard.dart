import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../state/providers/super_admin_auth_providers.dart';

/// Guards the SuperAdmin portal.
///
/// Verifies the current JWT carries `super_admin: true`.
/// If not, signs out and shows an access denied message.
/// The double-verification (JWT + this guard) is defense-in-depth per D2.
class SuperAdminGuard extends ConsumerWidget {
  final Widget child;

  const SuperAdminGuard({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSuperAdmin = ref.watch(isSuperAdminProvider);

    if (!isSuperAdmin) {
      // Sign out and deny access — user should not see any SuperAdmin UI.
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await Supabase.instance.client.auth.signOut();
        if (context.mounted) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      });

      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.block, size: 64, color: Colors.red),
              SizedBox(height: 16),
              Text(
                'Acesso negado.',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text('Este portal é restrito a Super Administradores.'),
            ],
          ),
        ),
      );
    }

    return child;
  }
}

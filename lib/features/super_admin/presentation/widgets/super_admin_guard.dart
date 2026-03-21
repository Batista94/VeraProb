import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../state/providers/super_admin_auth_providers.dart';
import '../../../admin/presentation/lock_screen.dart';

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
      final hasSession =
          Supabase.instance.client.auth.currentSession != null;

      if (!hasSession) {
        // Logout normal — sessão já foi limpa. Navega silenciosamente.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const AdminLockScreen()),
              (_) => false,
            );
          }
        });
        return const Scaffold(); // Tela em branco por 1 frame, imperceptível.
      }

      // Sessão ativa mas sem claim super_admin — acesso não autorizado (D2).
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await Supabase.instance.client.auth.signOut();
        if (context.mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const AdminLockScreen()),
            (_) => false,
          );
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

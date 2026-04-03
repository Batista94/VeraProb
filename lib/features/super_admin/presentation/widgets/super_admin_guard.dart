import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../state/providers/auth_providers.dart';
import '../../../../state/providers/super_admin_auth_providers.dart';
import '../../../admin/presentation/lock_screen.dart';
import '../screens/mfa_challenge_screen.dart';

/// Guards the SuperAdmin portal (INV-6 defense-in-depth).
///
/// Verifies two conditions:
/// 1. JWT carries `super_admin: true`
/// 2. Session is AAL2 (MFA verified)
///
/// If super_admin but not AAL2 → redirects to MfaChallengeScreen (legitimate
/// user, just needs MFA). If not super_admin → signs out and denies access.
class SuperAdminGuard extends ConsumerWidget {
  final Widget child;

  const SuperAdminGuard({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSuperAdmin = ref.watch(isSuperAdminProvider);
    final isAal2 = ref.watch(isSuperAdminAal2Provider);

    if (!isSuperAdmin) {
      final hasSession = ref.read(authRepositoryProvider).isAuthenticated;

      if (!hasSession) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const AdminLockScreen()),
              (_) => false,
            );
          }
        });
        return const Scaffold();
      }

      // Session active but no super_admin claim — unauthorized (D2).
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await ref.read(authRepositoryProvider).signOut();
        if (context.mounted) {
          await Navigator.of(context).pushAndRemoveUntil(
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

    // SuperAdmin but not AAL2 — redirect to MFA challenge (not "denied").
    if (!isAal2) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const MfaChallengeScreen()),
            (_) => false,
          );
        }
      });
      return const Scaffold();
    }

    return child;
  }
}

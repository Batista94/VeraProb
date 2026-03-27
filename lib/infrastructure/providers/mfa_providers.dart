import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../application/super_admin/mfa_challenge_handler.dart';
import '../../application/super_admin/mfa_enrollment_handler.dart';
import '../../domain/super_admin/i_mfa_repository.dart';
import '../../domain/super_admin/mfa_status.dart';
import '../super_admin/supabase_mfa_repository.dart';

/// Repository provider for MFA operations on SuperAdmin accounts.
///
/// INV-6: SuperAdmin access requires MFA + super_admin=true JWT claim.
final mfaRepositoryProvider = Provider<IMfaRepository>((ref) {
  return SupabaseMfaRepository(Supabase.instance.client);
});

/// Current MFA status — assurance level, enrollment state, lockout.
final mfaStatusProvider = FutureProvider<MfaStatus>((ref) async {
  final repo = ref.watch(mfaRepositoryProvider);
  return repo.getMfaStatus();
});

/// Handler for TOTP enrollment flow.
final mfaEnrollmentHandlerProvider = Provider<MfaEnrollmentHandler>((ref) {
  final repo = ref.watch(mfaRepositoryProvider);
  return MfaEnrollmentHandler(repo);
});

/// Handler for MFA challenge creation and TOTP verification.
final mfaChallengeHandlerProvider = Provider<MfaChallengeHandler>((ref) {
  final repo = ref.watch(mfaRepositoryProvider);
  return MfaChallengeHandler(repo);
});

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/features/super_admin/application/mfa_challenge_handler.dart';
import 'package:veraprob/features/super_admin/application/mfa_enrollment_handler.dart';
import 'package:veraprob/features/super_admin/domain/i_mfa_repository.dart';
import 'package:veraprob/features/super_admin/domain/mfa_status.dart';
import 'package:veraprob/infrastructure/providers/supabase_provider.dart';
import 'package:veraprob/features/super_admin/infrastructure/supabase_mfa_repository.dart';

/// INV-6: SuperAdmin access requires MFA + super_admin=true JWT claim.
final mfaRepositoryProvider = Provider<IMfaRepository>((ref) {
  return SupabaseMfaRepository(ref.watch(supabaseClientProvider));
});

final mfaStatusProvider = FutureProvider<MfaStatus>((ref) async {
  final repo = ref.watch(mfaRepositoryProvider);
  return repo.getMfaStatus();
});

final mfaEnrollmentHandlerProvider = Provider<MfaEnrollmentHandler>((ref) {
  final repo = ref.watch(mfaRepositoryProvider);
  return MfaEnrollmentHandler(repo);
});

final mfaChallengeHandlerProvider = Provider<MfaChallengeHandler>((ref) {
  final repo = ref.watch(mfaRepositoryProvider);
  return MfaChallengeHandler(repo);
});

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/application/super_admin/mfa_challenge_handler.dart';
import 'package:veraprob/application/super_admin/mfa_enrollment_handler.dart';
import 'package:veraprob/domain/super_admin/i_mfa_repository.dart';
import 'package:veraprob/domain/super_admin/mfa_status.dart';
import 'package:veraprob/infrastructure/super_admin/supabase_mfa_repository.dart';

/// INV-6: SuperAdmin access requires MFA + super_admin=true JWT claim.
final mfaRepositoryProvider = Provider<IMfaRepository>((ref) {
  return SupabaseMfaRepository(Supabase.instance.client);
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

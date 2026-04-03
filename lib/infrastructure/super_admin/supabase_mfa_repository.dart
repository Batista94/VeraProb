import 'dart:math';

import 'package:crypto/crypto.dart';
import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/super_admin/i_mfa_repository.dart';
import '../../domain/super_admin/mfa_challenge_result.dart';
import '../../domain/super_admin/mfa_enrollment_result.dart';
import '../../domain/super_admin/mfa_exception.dart';
import '../../domain/super_admin/mfa_status.dart';
import '../../domain/super_admin/mfa_verification_result.dart';

/// Supabase implementation of [IMfaRepository].
///
/// Uses Supabase's built-in MFA API (`auth.mfa.*`) for TOTP enrollment,
/// challenge creation, and verification. Circuit-breaker lockout is handled
/// by SECURITY DEFINER RPCs in PostgreSQL.
///
/// INV-6: SuperAdmin access requires MFA + super_admin=true JWT claim.
class SupabaseMfaRepository implements IMfaRepository {
  final SupabaseClient _client;

  SupabaseMfaRepository(this._client);

  @override
  Future<MfaEnrollmentResult> enrollTotp() async {
    try {
      final response = await _client.auth.mfa.enroll(
        factorType: FactorType.totp,
        issuer: 'VeraProb',
        friendlyName: 'VeraProb SuperAdmin TOTP',
      );

      final recoveryCodes = _generateRecoveryCodes();
      await _storeRecoveryCodeHashes(recoveryCodes);

      final totp = response.totp;
      if (totp == null) {
        throw StateError('TOTP data missing from enrollment response');
      }

      return MfaEnrollmentResult(
        factorId: response.id,
        totpUri: totp.uri,
        secret: totp.secret,
        recoveryCodes: recoveryCodes,
      );
    } on AuthException catch (e) {
      final isNotEnabled =
          e.code == 'mfa_totp_enroll_not_enabled' ||
          e.message.contains('MFA enroll is disabled');

      throw MfaException(e.message, code: e.code, isNotEnabled: isNotEnabled);
    } catch (e) {
      throw MfaException(e.toString());
    }
  }

  @override
  Future<MfaChallengeResult> createChallenge(String factorId) async {
    final response = await _client.auth.mfa.challenge(factorId: factorId);
    return MfaChallengeResult(challengeId: response.id, factorId: factorId);
  }

  @override
  Future<MfaVerificationResult> verifyChallenge({
    required String factorId,
    required String challengeId,
    required String code,
  }) async {
    // 1. Check circuit breaker
    final lockoutData =
        await _client.rpc(
              'check_mfa_lockout',
              params: {'p_user_id': _client.auth.currentUser!.id},
            )
            as Map<String, dynamic>;

    if (lockoutData['is_locked'] == true) {
      final lockedUntilRaw = lockoutData['locked_until'];
      return MfaVerificationFailure(
        failedAttempts: lockoutData['failed_attempts'] as int,
        isLockedOut: true,
        lockedUntil: lockedUntilRaw != null
            ? DateTime.parse(lockedUntilRaw as String)
            : null,
        message: 'Conta temporariamente bloqueada por tentativas falhas.',
      );
    }

    // 2. Attempt verification
    try {
      await _client.auth.mfa.verify(
        factorId: factorId,
        challengeId: challengeId,
        code: code,
      );

      // 3. Success — reset lockout
      await _client.rpc(
        'reset_mfa_lockout',
        params: {'p_user_id': _client.auth.currentUser!.id},
      );

      return const MfaVerificationSuccess();
    } on AuthException {
      // 4. Failure — record attempt
      final failureData =
          await _client.rpc(
                'record_mfa_failure',
                params: {'p_user_id': _client.auth.currentUser!.id},
              )
              as Map<String, dynamic>;

      final isLocked = failureData['is_locked'] == true;
      final lockedUntilRaw = failureData['locked_until'];

      return MfaVerificationFailure(
        failedAttempts: failureData['failed_attempts'] as int,
        isLockedOut: isLocked,
        lockedUntil: lockedUntilRaw != null
            ? DateTime.parse(lockedUntilRaw as String)
            : null,
        message: isLocked
            ? 'Conta bloqueada por 15 minutos após 5 tentativas falhas.'
            : 'Código TOTP inválido.',
      );
    }
  }

  @override
  Future<MfaStatus> getMfaStatus() async {
    final aalResponse = _client.auth.mfa.getAuthenticatorAssuranceLevel();
    final factorsResponse = await _client.auth.mfa.listFactors();

    final verifiedFactors = factorsResponse.totp
        .where((f) => f.status == FactorStatus.verified)
        .toList();
    final hasEnrolled = verifiedFactors.isNotEmpty;
    final factorId = hasEnrolled ? verifiedFactors.first.id : null;

    final currentLevel =
        aalResponse.currentLevel == AuthenticatorAssuranceLevels.aal2
        ? MfaAssuranceLevel.aal2
        : MfaAssuranceLevel.aal1;

    // Check lockout status
    var isLockedOut = false;
    var failedAttempts = 0;
    DateTime? lockedUntil;

    if (_client.auth.currentUser != null) {
      final lockoutData =
          await _client.rpc(
                'check_mfa_lockout',
                params: {'p_user_id': _client.auth.currentUser!.id},
              )
              as Map<String, dynamic>;

      isLockedOut = lockoutData['is_locked'] == true;
      failedAttempts = lockoutData['failed_attempts'] as int;
      final lockedUntilRaw = lockoutData['locked_until'];
      if (lockedUntilRaw != null) {
        lockedUntil = DateTime.parse(lockedUntilRaw as String);
      }
    }

    return MfaStatus(
      currentLevel: currentLevel,
      hasEnrolledFactor: hasEnrolled,
      factorId: factorId,
      isLockedOut: isLockedOut,
      failedAttempts: failedAttempts,
      lockedUntil: lockedUntil,
    );
  }

  // ── Private helpers ──────────────────────────────────────────────────────

  List<String> _generateRecoveryCodes() {
    final random = Random.secure();
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    return List.generate(10, (_) {
      return List.generate(
        8,
        (_) => chars[random.nextInt(chars.length)],
      ).join();
    });
  }

  Future<void> _storeRecoveryCodeHashes(List<String> codes) async {
    final userId = _client.auth.currentUser!.id;
    final rows = codes.map((code) {
      final hash = sha256.convert(utf8.encode(code)).toString();
      return {'user_id': userId, 'code_hash': hash};
    }).toList();

    for (final row in rows) {
      await _client.from('super_admin_recovery_codes').insert(row);
    }
  }
}

import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/super_admin/i_mfa_repository.dart';
import 'package:veraprob/domain/super_admin/mfa_challenge_result.dart';
import 'package:veraprob/domain/super_admin/mfa_verification_result.dart'
    as domain;
import 'package:veraprob/application/super_admin/mfa_result_view.dart';

/// Handles MFA challenge creation and TOTP verification for SuperAdmin.
///
/// INV-6: SuperAdmin access requires MFA + super_admin=true JWT claim.
/// INV-4: Pure orchestration — no direct DB access.
class MfaChallengeHandler {
  final IMfaRepository _repository;

  MfaChallengeHandler(this._repository);

  /// Creates a new TOTP challenge. Throws if not enrolled or locked out.
  Future<MfaChallengeResult> createChallenge() async {
    final status = await _repository.getMfaStatus();
    if (!status.hasEnrolledFactor || status.factorId == null) {
      throw const DomainException(
        'Nenhum fator TOTP cadastrado. Realize o cadastro primeiro.',
      );
    }
    if (status.isLockedOut) {
      throw const DomainException(
        'Conta temporariamente bloqueada por tentativas falhas.',
      );
    }
    return _repository.createChallenge(status.factorId!);
  }

  /// Verifies a TOTP code against a challenge.
  ///
  /// Returns a [MfaVerificationView] so the presentation layer never imports
  /// the domain [MfaVerificationResult] directly (C4 isolation).
  Future<MfaVerificationView> verify({
    required String factorId,
    required String challengeId,
    required String code,
  }) async {
    final result = await _repository.verifyChallenge(
      factorId: factorId,
      challengeId: challengeId,
      code: code,
    );
    return switch (result) {
      domain.MfaVerificationSuccess() => const MfaVerificationSuccess(),
      domain.MfaVerificationFailure(
        :final failedAttempts,
        :final isLockedOut,
        :final lockedUntil,
        :final message,
      ) =>
        MfaVerificationFailure(
          failedAttempts: failedAttempts,
          isLockedOut: isLockedOut,
          lockedUntil: lockedUntil,
          message: message,
        ),
    };
  }
}

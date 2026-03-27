import '../../domain/sla_audit/domain_exception.dart';
import '../../domain/super_admin/i_mfa_repository.dart';
import '../../domain/super_admin/mfa_enrollment_result.dart';

/// Handles TOTP enrollment for SuperAdmin accounts.
///
/// INV-6: SuperAdmin access requires MFA.
/// INV-4: Pure orchestration — no direct DB access.
class MfaEnrollmentHandler {
  final IMfaRepository _repository;

  MfaEnrollmentHandler(this._repository);

  /// Enrolls a new TOTP factor. Throws if already enrolled.
  Future<MfaEnrollmentResult> handle() async {
    final status = await _repository.getMfaStatus();
    if (status.hasEnrolledFactor) {
      throw const DomainException(
        'TOTP já cadastrado. Não é possível cadastrar novamente.',
      );
    }
    return _repository.enrollTotp();
  }
}

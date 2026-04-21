import 'dart:math';

import 'package:uuid/uuid.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/core/utils/date_time_provider.dart';
import 'package:veraprob/domain/enums/user_permissions.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/telegram/i_telegram_repository.dart';
import 'package:veraprob/domain/sla_audit/telegram/telegram_binding_token.dart';

import 'generate_telegram_binding_token_command.dart';

/// Generates a 15-minute 8-char binding code for a driver's Telegram chat.
///
/// Low-entropy code (40 bits via 32-char alphabet) is acceptable because of
/// the strict 15-minute TTL and DB-level rate limiting in the webhook.
/// Ambiguous characters (0/O, 1/I/L) are excluded for readability.
///
/// INV-1: Tenant validation is the first operation.
/// INV-7: ID and code are generated in Dart (deterministic replay).
class GenerateTelegramBindingTokenHandler {
  static const _alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  static const _codeLength = 8;
  static const _expiryMinutes = 15;

  final TenantValidationService _tenantValidator;
  final ITelegramRepository _telegramRepo;
  final RbacService _rbac;
  final IDateTimeProvider _dateTimeProvider;

  GenerateTelegramBindingTokenHandler({
    required TenantValidationService tenantValidator,
    required ITelegramRepository telegramRepo,
    required RbacService rbac,
    required IDateTimeProvider dateTimeProvider,
  }) : _tenantValidator = tenantValidator,
       _telegramRepo = telegramRepo,
       _rbac = rbac,
       _dateTimeProvider = dateTimeProvider;

  Future<TelegramBindingToken> handle(
    GenerateTelegramBindingTokenCommand command,
  ) async {
    // INV-1: Fail-Fast tenant validation.
    await _tenantValidator.assertTenantMatches(
      payloadOrgId: command.organizationId,
      sessionId: command.sessionId,
    );

    if (!_rbac.can(command.callerRole, UserPermission.canManageAssets)) {
      throw const DomainException('Unauthorized: canManageAssets required.');
    }

    final now = _dateTimeProvider.nowUtc();
    final code = _generateCode();

    final token = TelegramBindingToken(
      id: const Uuid().v4(),
      organizationId: command.organizationId,
      driverId: command.driverId,
      createdByUserId: command.callerUserId,
      code: code,
      expiresAtUtc: now.add(const Duration(minutes: _expiryMinutes)),
      usedAtUtc: null,
      createdAtUtc: now,
    );

    await _telegramRepo.createBindingToken(token);
    return token;
  }

  static String _generateCode() {
    final rng = Random.secure();
    return List.generate(
      _codeLength,
      (_) => _alphabet[rng.nextInt(_alphabet.length)],
    ).join();
  }
}

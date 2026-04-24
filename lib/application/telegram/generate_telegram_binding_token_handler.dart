import 'dart:math';

import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/core/utils/date_time_provider.dart';
import 'package:veraprob/core/utils/uuid_generator.dart';
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
/// INV-15: ID and code are generated via injected abstractions (deterministic replay).
class GenerateTelegramBindingTokenHandler {
  static const alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  static const codeLength = 8;
  static const _expiryMinutes = 15;
  static const maxRetries = 3;

  final TenantValidationService _tenantValidator;
  final ITelegramRepository _telegramRepo;
  final RbacService _rbac;
  final IDateTimeProvider _dateTimeProvider;
  final IUuidGenerator _uuidGenerator;
  final Random _random;

  GenerateTelegramBindingTokenHandler({
    required TenantValidationService tenantValidator,
    required ITelegramRepository telegramRepo,
    required RbacService rbac,
    required IDateTimeProvider dateTimeProvider,
    required IUuidGenerator uuidGenerator,
    Random? random,
  }) : _tenantValidator = tenantValidator,
       _telegramRepo = telegramRepo,
       _rbac = rbac,
       _dateTimeProvider = dateTimeProvider,
       _uuidGenerator = uuidGenerator,
       _random = random ?? Random.secure();

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

    // Retry loop: regenerate code on unique constraint violation (code collision).
    for (var attempt = 0; attempt < maxRetries; attempt++) {
      final code = generateCode();
      final token = TelegramBindingToken(
        id: _uuidGenerator.v4(),
        organizationId: command.organizationId,
        driverId: command.driverId,
        createdByUserId: command.callerUserId,
        code: code,
        expiresAtUtc: now.add(const Duration(minutes: _expiryMinutes)),
        usedAtUtc: null,
        createdAtUtc: now,
      );

      try {
        await _telegramRepo.createBindingToken(token);
        return token;
      } on DomainException catch (e) {
        final isCollision =
            e.message.contains('unique') ||
            e.message.contains('duplicate') ||
            e.message.contains('23505');
        if (!isCollision || attempt == maxRetries - 1) rethrow;
        // Collision: retry with a new code on next iteration.
      }
    }

    // Unreachable: loop always returns or rethrows. Dart requires this.
    throw const DomainException(
      'Code generation failed after $maxRetries retries',
    );
  }

  String generateCode() {
    return List.generate(
      codeLength,
      (_) => alphabet[_random.nextInt(alphabet.length)],
    ).join();
  }
}

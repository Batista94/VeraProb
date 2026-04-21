import 'telegram_binding_token.dart';

/// Persistence contract for Telegram bot integration.
///
/// INV-1: All operations are scoped to [organizationId].
/// INV-7: No DELETE or UPDATE — only INSERT and SELECT.
abstract class ITelegramRepository {
  /// Creates and persists a new binding token.
  Future<TelegramBindingToken> createBindingToken(TelegramBindingToken token);

  /// Returns the most recently created token for [driverId] (may be expired).
  Future<TelegramBindingToken?> findLatestTokenForDriver({
    required String driverId,
    required String organizationId,
  });

  /// Returns true if [driverId] has an active Telegram chat binding.
  Future<bool> hasActiveBinding({
    required String driverId,
    required String organizationId,
  });
}

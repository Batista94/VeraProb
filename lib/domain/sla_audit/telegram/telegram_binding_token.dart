import 'package:equatable/equatable.dart';

/// Short-lived 8-char binding code that an operator generates for a driver.
/// The driver types this code into the Telegram bot to link their chat_id.
///
/// Invariants:
/// - [code] is exactly 8 chars from the unambiguous alphabet
///   (A-Z excluding 0/O/1/I/L, plus 2-9).
/// - [expiresAtUtc] is at most 15 minutes after [createdAtUtc].
/// - [usedAtUtc] transitions NULL → timestamp exactly once (INV-7).
class TelegramBindingToken extends Equatable {
  final String id;
  final String organizationId;
  final String driverId;
  final String createdByUserId;
  final String code;
  final DateTime expiresAtUtc;
  final DateTime? usedAtUtc;
  final DateTime createdAtUtc;

  const TelegramBindingToken({
    required this.id,
    required this.organizationId,
    required this.driverId,
    required this.createdByUserId,
    required this.code,
    required this.expiresAtUtc,
    required this.usedAtUtc,
    required this.createdAtUtc,
  });

  bool isActiveAt(DateTime utcNow) =>
      usedAtUtc == null && utcNow.isBefore(expiresAtUtc);

  @override
  List<Object?> get props => [
    id,
    organizationId,
    driverId,
    createdByUserId,
    code,
    expiresAtUtc,
    usedAtUtc,
    createdAtUtc,
  ];
}

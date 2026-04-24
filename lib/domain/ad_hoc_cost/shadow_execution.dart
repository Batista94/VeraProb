import 'package:equatable/equatable.dart';
import 'shadow_execution_status.dart';

/// Traceable cost object for unlinked evidence events (INV-14).
///
/// Created when a Telegram evidence upload arrives with no matching
/// contractual execution. Represents real KM/time cost that must be
/// reconciled for financial accuracy.
///
/// operatorId (not driverId) per INV-14: transport-agnostic Core.
/// originChannel allows future WhatsApp/app ingestion paths.
class ShadowExecution extends Equatable {
  final String id;
  final String organizationId; // INV-1
  final String operatorId; // INV-14: not driverId
  final int chatId;
  final int telegramMessageId; // forensic chain anchor
  final String originEvidenceId;
  final String originChannel; // INV-14: 'telegram' | 'whatsapp' | 'app'
  final int messageTs; // device clock Unix epoch (INV-6)
  final DateTime countedFromUtc; // DB-set trusted anchor
  final ShadowExecutionStatus status;
  final String? reconciledExecutionId; // set_id of target execution
  final DateTime? reconciledAtUtc;
  final String? reconciledByUserId;
  final DateTime? dismissedAtUtc;
  final String? dismissedByUserId;
  final String? dismissedReason;
  final DateTime createdAtUtc;

  const ShadowExecution({
    required this.id,
    required this.organizationId,
    required this.operatorId,
    required this.chatId,
    required this.telegramMessageId,
    required this.originEvidenceId,
    this.originChannel = 'telegram',
    required this.messageTs,
    required this.countedFromUtc,
    this.status = ShadowExecutionStatus.unlinkedShadow,
    this.reconciledExecutionId,
    this.reconciledAtUtc,
    this.reconciledByUserId,
    this.dismissedAtUtc,
    this.dismissedByUserId,
    this.dismissedReason,
    required this.createdAtUtc,
  });

  bool get isTerminal =>
      status == ShadowExecutionStatus.reconciled ||
      status == ShadowExecutionStatus.dismissed;

  @override
  List<Object?> get props => [
    id,
    organizationId,
    operatorId,
    chatId,
    telegramMessageId,
    originEvidenceId,
    originChannel,
    messageTs,
    countedFromUtc,
    status,
    reconciledExecutionId,
    reconciledAtUtc,
    reconciledByUserId,
    dismissedAtUtc,
    dismissedByUserId,
    dismissedReason,
    createdAtUtc,
  ];
}

import 'package:equatable/equatable.dart';
import 'package:veraprob/domain/ad_hoc_cost/shadow_execution.dart';

/// Application-layer projection of ShadowExecution for OCC triage UI.
/// Features must use this type — never the domain entity directly (INV-13).
class ShadowExecutionSummary extends Equatable {
  final String id;
  final String organizationId;
  final String operatorId;
  final int messageTs;
  final int telegramMessageId;
  final String originChannel;

  const ShadowExecutionSummary({
    required this.id,
    required this.organizationId,
    required this.operatorId,
    required this.messageTs,
    required this.telegramMessageId,
    required this.originChannel,
  });

  factory ShadowExecutionSummary.fromDomain(ShadowExecution e) =>
      ShadowExecutionSummary(
        id: e.id,
        organizationId: e.organizationId,
        operatorId: e.operatorId,
        messageTs: e.messageTs,
        telegramMessageId: e.telegramMessageId,
        originChannel: e.originChannel,
      );

  @override
  List<Object?> get props => [
    id,
    organizationId,
    operatorId,
    messageTs,
    telegramMessageId,
    originChannel,
  ];
}

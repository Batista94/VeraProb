import 'package:veraprob/domain/sla_audit/dispute_reason_code.dart';
import 'package:veraprob/domain/sla_audit/dispute_reason_code_repository.dart';

/// In-memory implementation of [DisputeReasonCodeRepository].
///
/// Mirrors the closed global catalogue seeded by migration
/// `20260813000004_dispute_reason_codes.sql` (B6: agnostic codes; vertical
/// wording lives only in the labels). Used by in-memory persistence mode and
/// widget tests so the reason-code dropdown renders the same taxonomy as prod
/// without a live database.
class InMemoryDisputeReasonCodeRepository
    implements DisputeReasonCodeRepository {
  static const List<DisputeReasonCode> _catalogue = [
    DisputeReasonCode(
      code: 'FORCE_MAJEURE',
      category: 'ENVIRONMENTAL',
      labelPt: 'Força Maior',
      labelEn: 'Force Majeure',
      isActive: true,
      appliesTo: DisputeReasonContext.resolution,
    ),
    DisputeReasonCode(
      code: 'SENSOR_FAULT',
      category: 'TECHNICAL',
      labelPt: 'Falha de Sensor',
      labelEn: 'Sensor Fault',
      isActive: true,
      appliesTo: DisputeReasonContext.resolution,
    ),
    DisputeReasonCode(
      code: 'GPS_SIGNAL_LOSS',
      category: 'TECHNICAL',
      labelPt: 'Perda de Sinal GPS',
      labelEn: 'GPS Signal Loss',
      isActive: true,
      appliesTo: DisputeReasonContext.resolution,
    ),
    DisputeReasonCode(
      code: 'CONTRACT_EXCEPTION',
      category: 'CONTRACTUAL',
      labelPt: 'Exceção Contratual',
      labelEn: 'Contract Exception',
      isActive: true,
      appliesTo: DisputeReasonContext.all,
    ),
    DisputeReasonCode(
      code: 'ROUTE_DEVIATION',
      category: 'OPERATIONAL',
      labelPt: 'Desvio de Rota Autorizado',
      labelEn: 'Authorized Route Deviation',
      isActive: true,
      appliesTo: DisputeReasonContext.resolution,
    ),
    DisputeReasonCode(
      code: 'WEATHER_EVENT',
      category: 'ENVIRONMENTAL',
      labelPt: 'Evento Climático',
      labelEn: 'Weather Event',
      isActive: true,
      appliesTo: DisputeReasonContext.resolution,
    ),
    DisputeReasonCode(
      code: 'TRAFFIC_INCIDENT',
      category: 'OPERATIONAL',
      labelPt: 'Acidente/Interdição de Via',
      labelEn: 'Traffic Incident',
      isActive: true,
      appliesTo: DisputeReasonContext.resolution,
    ),
    DisputeReasonCode(
      code: 'ASSET_BREAKDOWN',
      category: 'TECHNICAL',
      labelPt: 'Pane do Ativo (Veículo)',
      labelEn: 'Asset Breakdown (Vehicle)',
      isActive: true,
      appliesTo: DisputeReasonContext.resolution,
    ),
    DisputeReasonCode(
      code: 'OPERATOR_EMERGENCY',
      category: 'OPERATIONAL',
      labelPt: 'Emergência do Operador',
      labelEn: 'Operator Emergency',
      isActive: true,
      appliesTo: DisputeReasonContext.resolution,
    ),
    DisputeReasonCode(
      code: 'REGULATORY_INTERVENTION',
      category: 'REGULATORY',
      labelPt: 'Intervenção Regulatória (Blitz)',
      labelEn: 'Regulatory Intervention',
      isActive: true,
      appliesTo: DisputeReasonContext.resolution,
    ),
    DisputeReasonCode(
      code: 'COMMUNICATION_FAILURE',
      category: 'TECHNICAL',
      labelPt: 'Falha de Comunicação',
      labelEn: 'Communication Failure',
      isActive: true,
      appliesTo: DisputeReasonContext.resolution,
    ),
    DisputeReasonCode(
      code: 'SCHEDULING_ERROR',
      category: 'OPERATIONAL',
      labelPt: 'Erro de Programação',
      labelEn: 'Scheduling Error',
      isActive: true,
      appliesTo: DisputeReasonContext.all,
    ),
    DisputeReasonCode(
      code: 'THIRD_PARTY_INCIDENT',
      category: 'OPERATIONAL',
      labelPt: 'Incidente com Terceiro',
      labelEn: 'Third-Party Incident',
      isActive: true,
      appliesTo: DisputeReasonContext.resolution,
    ),
    DisputeReasonCode(
      code: 'INFRASTRUCTURE_FAULT',
      category: 'OPERATIONAL',
      labelPt: 'Falha de Infraestrutura',
      labelEn: 'Infrastructure Fault',
      isActive: true,
      appliesTo: DisputeReasonContext.resolution,
    ),
    DisputeReasonCode(
      code: 'OTHER',
      category: 'OTHER',
      labelPt: 'Outro (ver comentário)',
      labelEn: 'Other (see comment)',
      isActive: true,
      appliesTo: DisputeReasonContext.all,
    ),
    DisputeReasonCode(
      code: 'LEGACY_UNCLASSIFIED',
      category: 'OTHER',
      labelPt: 'Legado Não Classificado',
      labelEn: 'Legacy Unclassified',
      isActive: true,
      appliesTo: DisputeReasonContext.all,
    ),
    DisputeReasonCode(
      code: 'INSUFFICIENT_EVIDENCE',
      category: 'OPERATIONAL',
      labelPt: 'Evidência Insuficiente',
      labelEn: 'Insufficient Evidence',
      isActive: true,
      appliesTo: DisputeReasonContext.rejection,
    ),
    DisputeReasonCode(
      code: 'POLICY_VIOLATION_CONFIRMED',
      category: 'CONTRACTUAL',
      labelPt: 'Violação de Política Confirmada',
      labelEn: 'Policy Violation Confirmed',
      isActive: true,
      appliesTo: DisputeReasonContext.rejection,
    ),
  ];

  @override
  Future<List<DisputeReasonCode>> findAllActive({
    String? organizationId,
  }) async {
    return _catalogue.where((c) => c.isActive).toList(growable: false);
  }
}

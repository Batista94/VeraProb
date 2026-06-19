/// Presentation util: maps raw `sla_audit_ledger` event type codes to
/// audit-grade Portuguese labels for the investigation timeline.
///
/// The raw enum is NEVER discarded — callers render this human label as the
/// primary line and keep the raw code as a monospace forensic subtitle
/// (MODO AUDITORIA citability). Unmapped codes fall back to the raw string so a
/// new event type degrades gracefully instead of vanishing.
String humanizeLedgerEventType(String type) {
  switch (type) {
    // ── Sanction verdict lifecycle ──────────────────────────────────────────
    case 'SANCTION_RECOMMENDED':
      return 'Infração Detectada pela Telemetria';
    case 'VERDICT_SEALED':
      return 'Veredito Confirmado pelo Auditor';
    case 'VERDICT_REFUSED':
      return 'Veredito Recusado (Isenção)';

    // ── Dispute lifecycle ───────────────────────────────────────────────────
    case 'SANCTION_DISPUTED':
      return 'Contestação Aberta';
    case 'DISPUTE_ACCEPTED':
      return 'Contestação Aceita (Multa Anulada)';
    case 'DISPUTE_OVERTURNED':
      return 'Contestação Negada (Multa Mantida)';
    case 'DISPUTE_RETRACTED':
      return 'Contestação Retratada';
    case 'DISPUTE_EVIDENCE_ATTACHED':
      return 'Evidência Anexada à Contestação';
    case 'EVIDENCE_HASH_MISMATCH':
      return 'Divergência de Assinatura Criptográfica';

    // ── Peer Review (Dual Control) ──────────────────────────────────────────
    case 'PEER_REVIEW_REQUESTED':
      return 'Revisão por Pares Solicitada (Duplo Controle)';
    case 'PEER_REVIEW_DECLINED':
      return 'Revisão por Pares Recusada';
    case 'PEER_REVIEW_CONFIRMED':
      return 'Revisão por Pares Confirmada';

    // ── Justification lifecycle ─────────────────────────────────────────────
    case 'JUSTIFICATION_SUBMITTED':
      return 'Justificativa Enviada';
    case 'JUSTIFICATION_APPROVED':
      return 'Justificativa Aprovada';
    case 'JUSTIFICATION_REJECTED':
      return 'Justificativa Rejeitada';
    case 'SLA_JUSTIFICATION_SUBMITTED':
      return 'Justificativa de SLA Enviada';
    case 'SLA_JUSTIFICATION_EXPIRED':
      return 'Prazo de Justificativa de SLA Expirado';

    // ── Execution lifecycle ─────────────────────────────────────────────────
    case 'OCCURRENCE_REGISTERED':
      return 'Ocorrência Registrada';
    case 'EXECUTION_BOUND':
      return 'Execução Vinculada ao Ativo';
    case 'EXECUTION_INHIBITED':
      return 'Execução Inibida';
    case 'TRANSIT_STARTED':
      return 'Trânsito Iniciado';
    case 'TRIP_INTERRUPTED':
      return 'Viagem Interrompida';
    case 'TRIP_CANCELLED':
      return 'Viagem Cancelada';
    case 'NO_SHOW_DECLARED':
      return 'Não Comparecimento Declarado';
    case 'COMPLETED_WITH_GAPS':
      return 'Concluído com Lacunas de Evidência';
    case 'EVIDENCE_GAP_DECLARED':
      return 'Lacuna de Evidência Declarada';

    // ── Contract lifecycle ──────────────────────────────────────────────────
    case 'PLAN_DECLARED':
      return 'Plano Declarado';
    case 'CONTRACT_CREATED':
      return 'Contrato Criado';
    case 'CONTRACT_SUBMITTED_FOR_APPROVAL':
      return 'Contrato Enviado para Aprovação';
    case 'CONTRACT_ACCEPTED_BY_CONTRACTOR':
      return 'Contrato Aceito pelo Transportador';
    case 'CONTRACT_ACTIVATED':
      return 'Contrato Ativado';
    case 'CONTRACT_CLOSED':
      return 'Contrato Encerrado';

    default:
      return type;
  }
}

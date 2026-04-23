/**
 * Compliance message formatter — pure functions, no I/O.
 * Extracted for testability. Used by handleStatusCheck and handleFinishCheck.
 *
 * INV-7: No dynamic types. All inputs are strictly typed.
 * INV-18: Category labels resolved from known map, never from Telegram input.
 */

export const CATEGORY_LABELS: Record<string, string> = {
  estado:    "Estado / Visual",
  doc:       "Documental / NF",
  oper:      "Operacional",
  incidente: "Incidente / SLA",
  outros:    "Outros / Info",
};

export interface ComplianceItem {
  type_key: string;
  is_fulfilled: boolean;
  count: number;
}

export type ComplianceRpcResult =
  | { status: "no_active_trip" }
  | { status: "no_requirements"; set_id: string; evidence_count: number }
  | { status: "active"; set_id: string; items: ComplianceItem[]; total_required: number; total_fulfilled: number };

/** Formats the /status checklist message body. Pure — no side effects. */
export function formatStatusMessage(result: ComplianceRpcResult): string {
  if (result.status === "no_active_trip") {
    return "📍 Você não possui rotas ativas no momento.\nO checklist de conformidade estará disponível assim que você iniciar uma viagem.";
  }

  if (result.status === "no_requirements") {
    const n = result.evidence_count;
    const s = n !== 1;
    return `✅ <b>${n}</b> evidência${s ? "s" : ""} enviada${s ? "s" : ""} e assinada${s ? "s" : ""} digitalmente nesta rota.`;
  }

  // active
  const { set_id, items, total_required, total_fulfilled } = result;
  const setIdShort = set_id.substring(0, 12);
  const pending = total_required - total_fulfilled;

  let body = `📋 <b>Conformidade de Rota: ${setIdShort}…</b>\n\n`;
  for (const item of items) {
    const label = CATEGORY_LABELS[item.type_key] ?? item.type_key;
    body += item.is_fulfilled
      ? `✅ ${label} (Enviado)\n`
      : `❌ <b>${label} (PENDENTE)</b>\n`;
  }

  body += pending > 0
    ? `\nFaltam <b>${pending}</b> evidência${pending !== 1 ? "s" : ""} para conformidade total.`
    : "\n🎉 <b>Checklist completo!</b> Todas as evidências obrigatórias foram enviadas.";

  return body;
}

/** Formats the /finish warning message when gaps exist. Pure — no side effects. */
export function formatFinishWarning(result: Extract<ComplianceRpcResult, { status: "active" }>): string {
  const pending = result.items.filter(i => !i.is_fulfilled);
  let msg = "⚠️ <b>Atenção:</b> Você ainda não enviou:\n\n";
  for (const item of pending) {
    const label = CATEGORY_LABELS[item.type_key] ?? item.type_key;
    msg += `❌ ${label}\n`;
  }
  return msg + "\nDeseja encerrar mesmo assim?";
}

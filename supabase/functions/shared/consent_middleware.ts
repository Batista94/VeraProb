/**
 * Consent Middleware (INV-3, INV-22, LGPD Art. 8)
 *
 * Version-aware LGPD gate for the Telegram Evidence Bot.
 * Fail-closed: if current published telegram_bot_terms consent cannot be
 * verified, processing is blocked.
 *
 * INV-3:  telegram_user_consents is append-only (immutable ledger).
 * INV-22: chat_id is user-scoped; org linkage is audit metadata only.
 */

import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

export type ActiveTelegramTerms = {
  id: string;
  version: string;
  title: string;
  body_markdown: string;
  content_sha256: string;
  published_at_utc: string;
};

/**
 * Returns true when the chat has accepted the *current* published
 * telegram_bot_terms version (fail-closed on any error).
 */
export async function checkConsent(
  supabase: SupabaseClient,
  chatId: number,
): Promise<boolean> {
  try {
    const { data, error } = await supabase.rpc("has_current_telegram_consent", {
      p_chat_id: chatId,
    });
    if (error) return false;
    return data === true;
  } catch {
    return false;
  }
}

/** Loads the active telegram_bot_terms document from legal_documents SSOT. */
export async function getActiveTelegramTerms(
  supabase: SupabaseClient,
): Promise<ActiveTelegramTerms | null> {
  try {
    const { data, error } = await supabase.rpc("get_active_telegram_bot_terms");
    if (error || data == null) return null;
    const row = data as ActiveTelegramTerms;
    if (!row.id || !row.body_markdown) return null;
    return row;
  } catch {
    return null;
  }
}

/** Records acceptance of the current (or specified) telegram_bot_terms. */
export async function acceptTelegramTerms(
  supabase: SupabaseClient,
  chatId: number,
  documentId?: string,
): Promise<boolean> {
  try {
    const { error } = await supabase.rpc("accept_telegram_bot_terms", {
      p_chat_id: chatId,
      p_document_id: documentId ?? null,
    });
    return error == null;
  } catch {
    return false;
  }
}

/** Appends a withdrawal row and unbinds the chat (Art. 8 §5). */
export async function withdrawTelegramConsent(
  supabase: SupabaseClient,
  chatId: number,
): Promise<boolean> {
  try {
    const { error } = await supabase.rpc("withdraw_telegram_bot_consent", {
      p_chat_id: chatId,
    });
    return error == null;
  } catch {
    return false;
  }
}

/** Converts markdown-ish body to a compact Telegram HTML message. */
export function formatTermsForTelegram(terms: ActiveTelegramTerms): string {
  const body = terms.body_markdown
    .replace(/^#+\s+/gm, "")
    .replace(/\*\*(.+?)\*\*/g, "<b>$1</b>")
    .trim();
  return (
    `⚖️ <b>${escapeHtml(terms.title)}</b>\n` +
    `<i>Versão ${escapeHtml(terms.version)}</i>\n\n` +
    body
  );
}

function escapeHtml(s: string): string {
  return s
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;");
}

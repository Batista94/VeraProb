/**
 * Consent Middleware (INV-3, INV-22)
 *
 * LGPD (Lei 13.709/2018) compliance gate.
 * Fail-closed: if consent cannot be verified, processing is blocked.
 *
 * INV-3:  telegram_user_consents is append-only (immutable ledger).
 * INV-22: No cross-tenant leakage — chat_id is user-scoped, not org-scoped.
 */

import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

/**
 * Checks whether a Telegram chat has accepted the consent terms.
 *
 * @param supabase - Service-role Supabase client
 * @param chatId - Telegram chat ID
 * @returns true if consent row exists, false otherwise (fail-closed)
 */
export async function checkConsent(
  supabase: SupabaseClient,
  chatId: number,
): Promise<boolean> {
  try {
    const { data, error } = await supabase
      .from("telegram_user_consents")
      .select("id")
      .eq("chat_id", chatId)
      .maybeSingle();

    if (error) return false;
    return data !== null;
  } catch {
    return false;
  }
}

/**
 * Edge Function: telegram-webhook
 * WS-4 Blindado: Heurística Temporal
 *
 * Changes vs pre-WS4:
 *   - Dead Zone Logic (INV-6): message.date replaces Date.now() as chronological anchor.
 *   - QA-Security Gate: validateMessageDate rejects future (>60s) or stale (>24h) timestamps.
 *   - Latest-Wins RPC: find_execution_for_telegram encapsulates join + retroactive -10min window.
 *   - Proactive Orphan Flag: requires_manual_link=true + TELEGRAM_ORPHAN alert when no execution found.
 *   - Feedback Diferencial: linked → receipt + execution_id; orphan → forensic receipt only (no anxiety).
 *   - Inline Keyboard: /help button always; orphan adds "Reportar ao Supervisor".
 *   - Audit Trail (INV-7): telegram_message_date recorded for discrepancy audit vs uploaded_at_utc.
 */

import { createClient } from "jsr:@supabase/supabase-js@2";

// ── Types ──────────────────────────────────────────────────────────────────────

interface TelegramPhotoSize {
  file_id: string;
  file_size?: number;
  width: number;
  height: number;
}

interface TelegramDocument {
  file_id: string;
  file_size?: number;
  file_name?: string; // NOT trusted (INV-18)
  mime_type?: string; // NOT trusted (INV-18)
}

interface TelegramVideo {
  file_id: string;
  file_size?: number;
  duration: number;
}

interface TelegramMessage {
  message_id: number;
  date: number; // Unix timestamp — device clock (INV-6 anchor)
  chat: { id: number };
  text?: string;
  photo?: TelegramPhotoSize[];
  document?: TelegramDocument;
  video?: TelegramVideo;
}

interface TelegramUpdate {
  update_id: number;
  message?: TelegramMessage;
}

interface InlineKeyboardButton {
  text: string;
  callback_data: string;
}

interface FileInfo {
  fileId: string;
  fileSize?: number;
}

interface ActiveBinding {
  driver_id: string;
  organization_id: string;
}

// ── Constants ──────────────────────────────────────────────────────────────────

const TELEGRAM_API = "https://api.telegram.org/bot";
const TG_FILE_SIZE_LIMIT = 10 * 1024 * 1024; // 10 MB
const BUCKET = "telegram_evidence";
const TS_FUTURE_TOLERANCE_S = 60;    // QA-Security: reject if > 60s in the future
const TS_MAX_DRIFT_S = 86_400;       // QA-Security: reject if > 24h old

// ── Main handler ───────────────────────────────────────────────────────────────

Deno.serve(async (req: Request): Promise<Response> => {
  const correlationId = crypto.randomUUID();
  const botToken = Deno.env.get("TELEGRAM_BOT_TOKEN")!;
  const webhookSecret = Deno.env.get("TELEGRAM_WEBHOOK_SECRET")!;

  // 1. Constant-time secret token validation (INV-18)
  const incomingSecret = req.headers.get("X-Telegram-Bot-Api-Secret-Token") ?? "";
  if (incomingSecret !== webhookSecret) {
    console.warn(`[telegram-webhook] unauthorized correlationId=${correlationId}`);
    return new Response("Unauthorized", { status: 401 });
  }

  // 2. Parse Telegram Update
  let update: TelegramUpdate;
  try {
    update = (await req.json()) as TelegramUpdate;
  } catch {
    return new Response("OK", { status: 200 });
  }

  const message = update.message || update.edited_message;
  if (!message) return new Response("OK", { status: 200 });

  const chatId = message.chat.id;

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // ── 3. /start command ─────────────────────────────────────────────────────
  if (message.text?.startsWith("/start")) {
    await sendMessageWithKeyboard(
      botToken, chatId,
      "Bem-vindo ao VeraProb Evidence Bot!\n\n" +
      "Envie o código de 8 caracteres gerado pelo operador no aplicativo VeraProb para vincular sua conta.\n\n" +
      "Após a vinculação, envie fotos ou documentos como evidência forense.",
      [[{ text: "❓ Ajuda", callback_data: "help" }]],
    );
    return new Response("OK", { status: 200 });
  }

  // ── 4. /help command ──────────────────────────────────────────────────────
  if (message.text?.startsWith("/help")) {
    await sendMessageWithKeyboard(
      botToken, chatId,
      "📋 <b>VeraProb Evidence Bot</b>\n\n" +
      "• Envie o código de 8 caracteres para vincular sua conta.\n" +
      "• Após vinculação, envie fotos, documentos ou vídeos como evidência.\n" +
      "• Cada envio gera um recibo forense com hash SHA-256.\n" +
      "• Em caso de dúvidas, contate seu supervisor.",
    );
    return new Response("OK", { status: 200 });
  }

  // ── 5. Text message — potential binding code ───────────────────────────────
  if (message.text && !message.text.startsWith("/")) {
    const code = message.text.trim().toUpperCase();

    if (/^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{8}$/.test(code)) {
      try {
        const { data, error } = await supabase.rpc(
          "consume_telegram_binding_token",
          { p_code: code, p_chat_id: chatId },
        );

        if (error) {
          const msg = error.message ?? "";
          if (msg.includes("expired")) {
            await sendMessageWithKeyboard(botToken, chatId,
              "Código expirado. Solicite um novo código no aplicativo VeraProb.",
              [[{ text: "❓ Ajuda", callback_data: "help" }]]);
          } else if (msg.includes("already been used")) {
            await sendMessageWithKeyboard(botToken, chatId,
              "Código já utilizado. Solicite um novo código no aplicativo.",
              [[{ text: "❓ Ajuda", callback_data: "help" }]]);
          } else if (msg.includes("not found")) {
            await sendMessageWithKeyboard(botToken, chatId,
              "Código inválido. Verifique e tente novamente.",
              [[{ text: "❓ Ajuda", callback_data: "help" }]]);
          } else {
            console.error(`[telegram-webhook] bind RPC error correlationId=${correlationId}:`, error);
            await sendMessageWithKeyboard(botToken, chatId, "Erro ao processar o código. Tente novamente.");
          }
        } else if (data && (data as unknown[]).length > 0) {
          await sendMessageWithKeyboard(
            botToken, chatId,
            "✅ Vinculação realizada com sucesso!\nAgora você pode enviar fotos ou documentos como evidência forense.",
            [[{ text: "❓ Ajuda", callback_data: "help" }]],
          );
        }
      } catch (e) {
        console.error(`[telegram-webhook] bind error correlationId=${correlationId}:`, e);
        await sendMessageWithKeyboard(botToken, chatId, "Erro interno. Tente novamente.");
      }
    } else {
      const binding = await getActiveBinding(supabase, chatId);
      await sendMessageWithKeyboard(
        botToken, chatId,
        binding
          ? "Para enviar evidências, anexe uma foto ou documento."
          : "Chat não vinculado. Envie o código de 8 caracteres do aplicativo VeraProb.",
        [[{ text: "❓ Ajuda", callback_data: "help" }]],
      );
    }
    return new Response("OK", { status: 200 });
  }

  // ── 6. Photo / Document / Video — evidence upload ─────────────────────────
  const fileInfo = extractFileInfo(message);
  if (!fileInfo) return new Response("OK", { status: 200 });

  // 6a. WS-4 QA-Security Gate: validate message.date BEFORE any processing (INV-6)
  const tsValidation = validateMessageDate(message.date);
  if (!tsValidation.valid) {
    console.warn(`[telegram-webhook] timestamp rejected correlationId=${correlationId} reason=${tsValidation.reason}`);
    await sendMessageWithKeyboard(
      botToken, chatId,
      "⚠️ Não foi possível registrar esta evidência.\nVerifique o horário do seu dispositivo e tente novamente.",
      [[{ text: "❓ Ajuda", callback_data: "help" }]],
    );
    return new Response("OK", { status: 200 });
  }

  // 6b. Resolve active binding — org_id from DB, never from Telegram (INV-18).
  const binding = await getActiveBinding(supabase, chatId);
  if (!binding) {
    await sendMessageWithKeyboard(
      botToken, chatId,
      "Chat não vinculado. Envie o código do aplicativo VeraProb primeiro.",
      [[{ text: "❓ Ajuda", callback_data: "help" }]],
    );
    return new Response("OK", { status: 200 });
  }

  // 6c. Pre-download size check.
  if (fileInfo.fileSize && fileInfo.fileSize > TG_FILE_SIZE_LIMIT) {
    await sendMessageWithKeyboard(botToken, chatId,
      `Arquivo muito grande (${Math.round(fileInfo.fileSize / 1024 / 1024)} MB). Limite: 10 MB.`);
    return new Response("OK", { status: 200 });
  }

  // 6d. DB-backed rate limit.
  const { data: allowed } = await supabase.rpc("check_telegram_rate_limit", { p_chat_id: chatId });
  if (!allowed) {
    await sendMessageWithKeyboard(botToken, chatId,
      "Limite de envio atingido. Aguarde 1 minuto antes de enviar novamente.");
    return new Response("OK", { status: 200 });
  }

  try {
    // 6e. Fetch file path from Telegram API.
    const filePath = await getTelegramFilePath(botToken, fileInfo.fileId);

    // 6f. Download file bytes.
    const fileBytes = await downloadTelegramFile(botToken, filePath);

    if (fileBytes.byteLength > TG_FILE_SIZE_LIMIT) {
      await sendMessageWithKeyboard(botToken, chatId, "Arquivo excede 10 MB após download. Operação cancelada.");
      return new Response("OK", { status: 200 });
    }

    const byteArray = new Uint8Array(fileBytes);

    // 6g. SHA-256 hash — server-authoritative (INV-9, INV-18).
    const hashBuffer = await crypto.subtle.digest("SHA-256", fileBytes);
    const hashHex = Array.from(new Uint8Array(hashBuffer))
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("");

    // 6h. Server-generated filename — Telegram metadata ignored (INV-18).
    const ext = sniffExtension(byteArray);
    
    if (ext === "bin") {
      console.warn(`[telegram-webhook] unsupported format correlationId=${correlationId}`);
      await sendMessageWithKeyboard(
        botToken, chatId,
        "⚠️ <b>Formato não suportado.</b>\nPor favor, envie apenas fotos (JPG/PNG), vídeos (MP4) ou documentos PDF.",
        [[{ text: "❓ Ajuda", callback_data: "help" }]],
      );
      return new Response("OK", { status: 200 });
    }

    const serverFileName = `${crypto.randomUUID()}.${ext}`;
    const storagePath = `${binding.organization_id}/telegram/${chatId}/${serverFileName}`;

    // 6i. Upload to Supabase Storage.
    const { error: uploadError } = await supabase.storage
      .from(BUCKET)
      .upload(storagePath, fileBytes, { contentType: mimeFromExt(ext), upsert: false });

    if (uploadError) {
      console.error(`[telegram-webhook] storage upload error correlationId=${correlationId}:`, uploadError);
      await sendMessageWithKeyboard(botToken, chatId, "Erro ao armazenar evidência. Tente novamente.");
      return new Response("OK", { status: 200 });
    }

    // 6j. WS-4 Dead Zone Logic: use message.date (device clock) as chronological anchor (INV-6).
    //     RPC encapsulates Latest-Wins + retroactive -10min window.
    const linkedSetId = await findExecutionForTelegram(
      supabase,
      binding.organization_id,
      binding.driver_id,
      message.date,
      correlationId,
    );
    const requiresManualLink = linkedSetId === null;

    // 6k. Insert evidence record — idempotent via UNIQUE (chat_id, telegram_message_id).
    //     telegram_message_date = device timestamp (INV-6 audit anchor).
    const { error: insertError } = await supabase
      .from("telegram_evidence_uploads")
      .insert({
        organization_id: binding.organization_id,
        driver_id: binding.driver_id,
        chat_id: chatId,
        telegram_message_id: message.message_id,
        file_name: serverFileName,
        forensic_hash: hashHex,
        storage_path: storagePath,
        source: "telegram",
        linked_set_id: linkedSetId ?? null,
        telegram_message_date: new Date(message.date * 1000).toISOString(), // INV-6: device clock
        requires_manual_link: requiresManualLink,
        // uploaded_at_utc: omitted — DB DEFAULT NOW() is the ingest anchor for discrepancy audit
      });

    if (insertError) {
      if (insertError.code === "23505") {
        // Idempotent retry — evidence already committed (INV-15).
        await sendMessageWithKeyboard(botToken, chatId, "📎 Evidência já registrada anteriormente.");
      } else {
        console.error(`[telegram-webhook] insert error correlationId=${correlationId}:`, insertError);
        await sendMessageWithKeyboard(botToken, chatId, "Erro ao registrar evidência. Tente novamente.");
      }
      return new Response("OK", { status: 200 });
    }

    // 6l. WS-4 Proactive Orphan Flag: fire TELEGRAM_ORPHAN alert when no execution found.
    if (requiresManualLink) {
      await fireOrphanAlert(supabase, binding.organization_id, chatId, hashHex, correlationId);
    }

    // 6m. WS-4 Feedback Diferencial:
    //     Linked  → receipt + execution_id (confirms forensic chain)
    //     Orphan  → forensic receipt only (strategic silence — no anxiety)
    if (linkedSetId) {
      await sendMessageWithKeyboard(
        botToken, chatId,
        `✅ <b>Evidência registrada</b>\n` +
        `🔐 Hash: <code>${hashHex.substring(0, 16)}…</code>\n` +
        `📋 Execução: <code>${linkedSetId}</code>`,
        [[{ text: "❓ Ajuda", callback_data: "help" }]],
      );
    } else {
      await sendMessageWithKeyboard(
        botToken, chatId,
        `📎 <b>Recibo Forense</b>\n` +
        `🔐 Hash: <code>${hashHex.substring(0, 16)}…</code>`,
        [
          [{ text: "❓ Ajuda", callback_data: "help" }],
          [{ text: "📣 Reportar ao Supervisor", callback_data: "report_orphan" }],
        ],
      );
    }
  } catch (e) {
    console.error(`[telegram-webhook] evidence processing error correlationId=${correlationId}:`, e);
    await sendMessageWithKeyboard(botToken, chatId, "Erro ao processar evidência. Tente novamente.");
  }

  return new Response("OK", { status: 200 });
});

// ── WS-4 Core Functions ────────────────────────────────────────────────────────

/**
 * QA-Security Gate (INV-6, INV-18):
 * Rejects timestamps that are in the future (>60s) or excessively stale (>24h).
 * Uses device clock (message.date) as the forensic anchor — not Date.now().
 */
function validateMessageDate(messageUnixTs: number): { valid: boolean; reason?: string } {
  const nowS = Date.now() / 1000;
  if (messageUnixTs > nowS + TS_FUTURE_TOLERANCE_S) {
    return { valid: false, reason: `future_timestamp: ${messageUnixTs} > ${nowS + TS_FUTURE_TOLERANCE_S}` };
  }
  if (nowS - messageUnixTs > TS_MAX_DRIFT_S) {
    return { valid: false, reason: `stale_timestamp: drift=${Math.round(nowS - messageUnixTs)}s` };
  }
  return { valid: true };
}

/**
 * WS-4 Dead Zone Logic (INV-6):
 * Delegates to RPC find_execution_for_telegram which implements:
 *   - Retroactive window: [message_ts - 10min, message_ts + 4h]
 *   - Latest-Wins: ORDER BY window_start_utc DESC LIMIT 1
 * Failure never blocks evidence ingestion.
 */
async function findExecutionForTelegram(
  supabase: ReturnType<typeof createClient>,
  orgId: string,
  driverId: string,
  messageUnixTs: number,
  correlationId: string,
): Promise<string | null> {
  try {
    const { data, error } = await supabase.rpc("find_execution_for_telegram", {
      p_org_id: orgId,
      p_driver_id: driverId,
      p_message_ts: messageUnixTs,
    });
    if (error) {
      console.warn(`[telegram-webhook] find_execution_for_telegram error correlationId=${correlationId}:`, error);
      return null;
    }
    return (data as string | null) ?? null;
  } catch {
    return null;
  }
}

/**
 * WS-4 Proactive Orphan Flag:
 * Inserts a TELEGRAM_ORPHAN alert for supervisor triage.
 * Uses (chat_id as entity_id, correlationId as triggering_event_id) for idempotency.
 * Failure is non-blocking — evidence is already committed.
 */
async function fireOrphanAlert(
  supabase: ReturnType<typeof createClient>,
  orgId: string,
  chatId: number,
  forensicHash: string,
  correlationId: string,
): Promise<void> {
  try {
    await supabase.from("operational_alerts").insert({
      organization_id: orgId,
      entity_id: String(chatId),
      contract_id: "TELEGRAM_ORPHAN",
      alert_type: "TELEGRAM_ORPHAN",
      severity: "WARNING",
      status: "ACTIVE",
      source: "telegram",
      triggering_event_id: correlationId,
      context: {
        correlation_id: correlationId,
        forensic_hash_prefix: forensicHash.substring(0, 16),
        chat_id: chatId,
      },
    });
  } catch (e) {
    // Non-blocking: evidence is sealed. Alert failure is logged only.
    console.warn(`[telegram-webhook] orphan alert insert failed correlationId=${correlationId}:`, e);
  }
}

// ── Helpers ────────────────────────────────────────────────────────────────────

function extractFileInfo(message: TelegramMessage): FileInfo | null {
  if (message.photo?.length) {
    const largest = message.photo[message.photo.length - 1];
    return { fileId: largest.file_id, fileSize: largest.file_size };
  }
  if (message.document) return { fileId: message.document.file_id, fileSize: message.document.file_size };
  if (message.video) return { fileId: message.video.file_id, fileSize: message.video.file_size };
  return null;
}

async function getActiveBinding(
  supabase: ReturnType<typeof createClient>,
  chatId: number,
): Promise<ActiveBinding | null> {
  const { data } = await supabase
    .from("telegram_chat_bindings")
    .select("driver_id, organization_id")
    .eq("chat_id", chatId)
    .is("unbound_at_utc", null)
    .limit(1)
    .maybeSingle();
  return data as ActiveBinding | null;
}

async function getTelegramFilePath(botToken: string, fileId: string): Promise<string> {
  const resp = await fetch(`${TELEGRAM_API}${botToken}/getFile?file_id=${fileId}`);
  const json = await resp.json();
  if (!json.ok) throw new Error(`getFile failed: ${json.description}`);
  return json.result.file_path as string;
}

async function downloadTelegramFile(botToken: string, filePath: string): Promise<ArrayBuffer> {
  const resp = await fetch(`https://api.telegram.org/file/bot${botToken}/${filePath}`);
  if (!resp.ok) throw new Error(`File download failed: ${resp.status}`);
  return resp.arrayBuffer();
}

/**
 * WS-4 UX-Operations: Inline Keyboard support.
 * parse_mode HTML for bold/code formatting in receipts.
 * Fire-and-forget — sendMessage failure never blocks evidence processing.
 */
async function sendMessageWithKeyboard(
  botToken: string,
  chatId: number,
  text: string,
  inlineKeyboard?: InlineKeyboardButton[][],
): Promise<void> {
  try {
    const body: Record<string, unknown> = {
      chat_id: chatId,
      text,
      parse_mode: "HTML",
    };
    if (inlineKeyboard?.length) {
      body.reply_markup = { inline_keyboard: inlineKeyboard };
    }
    await fetch(`${TELEGRAM_API}${botToken}/sendMessage`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
  } catch {
    // Fire-and-forget.
  }
}

/**
 * Sniffs file extension from magic bytes (INV-18: never trust Telegram metadata).
 */
function sniffExtension(bytes: Uint8Array): string {
  if (bytes[0] === 0xFF && bytes[1] === 0xD8 && bytes[2] === 0xFF) return "jpg";
  if (bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4E && bytes[3] === 0x47) return "png";
  if (bytes[0] === 0x25 && bytes[1] === 0x50 && bytes[2] === 0x44 && bytes[3] === 0x46) return "pdf";
  if (
    bytes[0] === 0x52 && bytes[1] === 0x49 && bytes[2] === 0x46 && bytes[3] === 0x46 &&
    bytes[8] === 0x57 && bytes[9] === 0x45 && bytes[10] === 0x42 && bytes[11] === 0x50
  ) return "webp";
  if (
    bytes.length >= 12 &&
    bytes[4] === 0x66 && bytes[5] === 0x74 && bytes[6] === 0x79 && bytes[7] === 0x70
  ) {
    const brand = String.fromCharCode(bytes[8], bytes[9], bytes[10], bytes[11]);
    const heicBrands = ["heic", "heix", "hevc", "hevx", "mif1", "msf1", "MiHE", "MiHA"];
    if (heicBrands.some((b) => brand === b || brand.startsWith(b.substring(0, 4)))) return "heic";
    return "mp4";
  }
  return "bin";
}

function mimeFromExt(ext: string): string {
  const map: Record<string, string> = {
    jpg: "image/jpeg", png: "image/png", pdf: "application/pdf",
    mp4: "video/mp4", webp: "image/webp", heic: "image/heic",
    bin: "application/octet-stream",
  };
  return map[ext] ?? "application/octet-stream";
}

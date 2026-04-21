/**
 * Edge Function: telegram-webhook
 *
 * Forensic ingestion point for driver evidence submitted via Telegram.
 *
 * Security model:
 *   - X-Telegram-Bot-Api-Secret-Token validated via constant-time comparison
 *     before any processing (prevents timing oracle attacks).
 *   - Always returns HTTP 200 to Telegram (non-2xx triggers retries → duplicates).
 *   - Zero-Trust: Telegram file metadata (filename, MIME type) is never trusted.
 *     Extension sniffed from magic bytes server-side (INV-18).
 *   - Multi-tenancy: org_id resolved from DB binding, never from Telegram payload.
 *   - Rate limit: 10 uploads per chat_id per 60s checked against committed DB rows.
 *
 * Why handleWithSecurity() is NOT used:
 *   Telegram posts without a Supabase JWT. The shared wrapper requires JWT auth
 *   and its error-mapping behaviour conflicts with the mandatory HTTP 200 contract.
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
  date: number; // Unix timestamp
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

// ── Main handler ───────────────────────────────────────────────────────────────

Deno.serve(async (req: Request): Promise<Response> => {
  const correlationId = crypto.randomUUID();

  // ── 1. Constant-time secret token validation ───────────────────────────────
  const incomingSecret = req.headers.get("X-Telegram-Bot-Api-Secret-Token") ?? "";
  const expectedSecret = Deno.env.get("TELEGRAM_WEBHOOK_SECRET") ?? "";

  const enc = new TextEncoder();
  const expectedBytes = enc.encode(expectedSecret);
  const incomingBytes = enc.encode(incomingSecret);

  let secretValid = true;
  if (expectedBytes.length !== incomingBytes.length) {
    secretValid = false;
  }
  
  let result = 0;
  for (let i = 0; i < expectedBytes.length; i++) {
    const a = expectedBytes[i];
    const b = i < incomingBytes.length ? incomingBytes[i] : 0;
    result |= a ^ b;
  }
  
  if (result !== 0) {
    secretValid = false;
  }

  if (!secretValid) {
    // Return 200 — Telegram should not retry (the request was received).
    return new Response("OK", { status: 200 });
  }

  // ── 2. Parse Telegram Update ───────────────────────────────────────────────
  let update: TelegramUpdate;
  try {
    update = (await req.json()) as TelegramUpdate;
  } catch {
    return new Response("OK", { status: 200 });
  }

  const message = update.message;
  if (!message) {
    return new Response("OK", { status: 200 });
  }

  const chatId = message.chat.id;
  const botToken = Deno.env.get("TELEGRAM_BOT_TOKEN")!;

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // ── 3. /start command ─────────────────────────────────────────────────────
  if (message.text?.startsWith("/start")) {
    await sendMessage(
      botToken,
      chatId,
      "Bem-vindo ao VeraProb Evidence Bot!\n\n" +
        "Para vincular sua conta, envie o código de 8 caracteres " +
        "que o operador gerou para você no aplicativo VeraProb.\n\n" +
        "Após a vinculação, envie fotos ou documentos como evidência forense.",
    );
    return new Response("OK", { status: 200 });
  }

  // ── 4. Text message — potential binding code ───────────────────────────────
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
            await sendMessage(
              botToken,
              chatId,
              "Código expirado. Solicite um novo código no aplicativo VeraProb.",
            );
          } else if (msg.includes("already been used")) {
            await sendMessage(
              botToken,
              chatId,
              "Código já utilizado. Solicite um novo código no aplicativo.",
            );
          } else if (msg.includes("not found")) {
            await sendMessage(
              botToken,
              chatId,
              "Código inválido. Verifique e tente novamente.",
            );
          } else {
            console.error(
              `[telegram-webhook] bind RPC error correlationId=${correlationId}:`,
              error,
            );
            await sendMessage(botToken, chatId, "Erro ao processar o código. Tente novamente.");
          }
        } else if (data && (data as unknown[]).length > 0) {
          await sendMessage(
            botToken,
            chatId,
            "Vinculação realizada com sucesso!\n" +
              "Agora você pode enviar fotos ou documentos como evidência forense.",
          );
        }
      } catch (e) {
        console.error(
          `[telegram-webhook] bind error correlationId=${correlationId}:`,
          e,
        );
        await sendMessage(botToken, chatId, "Erro interno. Tente novamente.");
      }
    } else {
      const binding = await getActiveBinding(supabase, chatId);
      if (binding) {
        await sendMessage(
          botToken,
          chatId,
          "Para enviar evidências, anexe uma foto ou documento.",
        );
      } else {
        await sendMessage(
          botToken,
          chatId,
          "Chat não vinculado. Envie o código de 8 caracteres do aplicativo VeraProb.",
        );
      }
    }
    return new Response("OK", { status: 200 });
  }

  // ── 5. Photo / Document / Video — evidence upload ─────────────────────────
  const fileInfo = extractFileInfo(message);

  if (!fileInfo) {
    return new Response("OK", { status: 200 });
  }

  // 5a. Resolve active binding — org_id comes from DB, never from Telegram (INV-18).
  const binding = await getActiveBinding(supabase, chatId);
  if (!binding) {
    await sendMessage(
      botToken,
      chatId,
      "Chat não vinculado. Envie o código do aplicativo VeraProb primeiro.",
    );
    return new Response("OK", { status: 200 });
  }

  // 5b. Pre-download size check.
  if (fileInfo.fileSize && fileInfo.fileSize > TG_FILE_SIZE_LIMIT) {
    await sendMessage(
      botToken,
      chatId,
      `Arquivo muito grande (${Math.round(fileInfo.fileSize / 1024 / 1024)} MB). Limite: 10 MB.`,
    );
    return new Response("OK", { status: 200 });
  }

  // 5c. DB-backed rate limit: 10 uploads per chat per 60s.
  const { data: allowed } = await supabase.rpc("check_telegram_rate_limit", {
    p_chat_id: chatId,
  });
  if (!allowed) {
    await sendMessage(
      botToken,
      chatId,
      "Limite de envio atingido. Aguarde 1 minuto antes de enviar novamente.",
    );
    return new Response("OK", { status: 200 });
  }

  try {
    // 5d. Fetch file path from Telegram API.
    const filePath = await getTelegramFilePath(botToken, fileInfo.fileId);

    // 5e. Download file bytes.
    const fileBytes = await downloadTelegramFile(botToken, filePath);

    // 5f. Post-download size check (belt-and-suspenders).
    if (fileBytes.byteLength > TG_FILE_SIZE_LIMIT) {
      await sendMessage(botToken, chatId, "Arquivo excede 10 MB após download. Operação cancelada.");
      return new Response("OK", { status: 200 });
    }

    const byteArray = new Uint8Array(fileBytes);

    // 5g. SHA-256 hash in-memory — server-authoritative (INV-9, INV-18).
    const hashBuffer = await crypto.subtle.digest("SHA-256", fileBytes);
    const hashHex = Array.from(new Uint8Array(hashBuffer))
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("");

    // 5h. Server-generated filename — Telegram metadata is ignored (INV-18).
    const ext = sniffExtension(byteArray);
    const serverFileName = `${crypto.randomUUID()}.${ext}`;
    const storagePath =
      `${binding.organization_id}/telegram/${chatId}/${serverFileName}`;

    // 5i. Upload to Supabase Storage.
    const { error: uploadError } = await supabase.storage
      .from(BUCKET)
      .upload(storagePath, fileBytes, {
        contentType: mimeFromExt(ext),
        upsert: false,
      });

    if (uploadError) {
      console.error(
        `[telegram-webhook] storage upload error correlationId=${correlationId}:`,
        uploadError,
      );
      await sendMessage(botToken, chatId, "Erro ao armazenar evidência. Tente novamente.");
      return new Response("OK", { status: 200 });
    }

    // 5j. Best-effort verdict window link (never blocks ingestion).
    const linkedSetId = await findLinkedSetId(
      supabase,
      binding.organization_id,
      binding.driver_id,
      message.date,
    );

    // 5k. Insert evidence record — idempotent via UNIQUE (chat_id, telegram_message_id).
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
        uploaded_at_utc: new Date().toISOString(),
      });

    if (insertError) {
      if (insertError.code === "23505") {
        // Idempotent retry — evidence already committed.
        await sendMessage(botToken, chatId, "Evidência já registrada anteriormente.");
      } else {
        console.error(
          `[telegram-webhook] insert error correlationId=${correlationId}:`,
          insertError,
        );
        await sendMessage(botToken, chatId, "Erro ao registrar evidência. Tente novamente.");
      }
      return new Response("OK", { status: 200 });
    }

    // 5l. Send forensic receipt to driver (Proof of Receipt).
    await sendMessage(
      botToken,
      chatId,
      `Evidência registrada com sucesso.\n` +
        `Hash SHA-256: ${hashHex.substring(0, 16)}...\n` +
        (linkedSetId
          ? `Execução vinculada: ${linkedSetId}`
          : "Nenhuma execução identificada na janela de 4h."),
    );
  } catch (e) {
    console.error(
      `[telegram-webhook] evidence processing error correlationId=${correlationId}:`,
      e,
    );
    await sendMessage(botToken, chatId, "Erro ao processar evidência. Tente novamente.");
  }

  return new Response("OK", { status: 200 });
});

// ── Helpers ────────────────────────────────────────────────────────────────────

function extractFileInfo(message: TelegramMessage): FileInfo | null {
  // Photo: array of PhotoSize — largest is last.
  if (message.photo?.length) {
    const largest = message.photo[message.photo.length - 1];
    return { fileId: largest.file_id, fileSize: largest.file_size };
  }
  if (message.document) {
    return { fileId: message.document.file_id, fileSize: message.document.file_size };
  }
  if (message.video) {
    return { fileId: message.video.file_id, fileSize: message.video.file_size };
  }
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

async function findLinkedSetId(
  supabase: ReturnType<typeof createClient>,
  orgId: string,
  _driverId: string,
  messageUnixTs: number,
): Promise<string | null> {
  // Best-effort heuristic: find a non-terminal execution set within ±4h of message.
  // execution_states has no driver_id column; this is a time-window approximation.
  // Failure never blocks evidence ingestion.
  try {
    const windowStart = new Date((messageUnixTs - 4 * 3600) * 1000).toISOString();
    const windowEnd = new Date((messageUnixTs + 4 * 3600) * 1000).toISOString();

    const { data } = await supabase
      .from("execution_states")
      .select("set_id")
      .eq("organization_id", orgId)
      .in("status", ["pending", "executed", "evidenceGap"])
      .gte("window_end_utc", windowStart)
      .lte("window_start_utc", windowEnd)
      .order("window_start_utc", { ascending: false })
      .limit(1)
      .maybeSingle();

    return (data as { set_id: string } | null)?.set_id ?? null;
  } catch {
    return null;
  }
}

/**
 * Sniffs file extension from magic bytes (INV-18: never trust Telegram metadata).
 *
 * HEIC/HEIF note: Telegram converts "Photo" type to JPEG automatically.
 * When drivers send as "File/Document", HEIC arrives as raw ISOBMFF container.
 * HEIC/HEIF do NOT have magic bytes at offset 0 — detection uses the ftyp box
 * at bytes 4–11: ftyp (4-7) + major brand (8-11).
 */
function sniffExtension(bytes: Uint8Array): string {
  // JPEG: FF D8 FF
  if (bytes[0] === 0xFF && bytes[1] === 0xD8 && bytes[2] === 0xFF) return "jpg";
  // PNG: 89 50 4E 47
  if (bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4E && bytes[3] === 0x47) {
    return "png";
  }
  // PDF: 25 50 44 46
  if (bytes[0] === 0x25 && bytes[1] === 0x50 && bytes[2] === 0x44 && bytes[3] === 0x46) {
    return "pdf";
  }
  // WebP: RIFF at 0-3, WEBP at 8-11
  if (
    bytes[0] === 0x52 && bytes[1] === 0x49 && bytes[2] === 0x46 && bytes[3] === 0x46 &&
    bytes[8] === 0x57 && bytes[9] === 0x45 && bytes[10] === 0x42 && bytes[11] === 0x50
  ) {
    return "webp";
  }
  // ISO BMFF ftyp box (covers HEIC, HEIF, MP4, MOV, M4A).
  // Box structure: [size 4B][ftyp 4B][major_brand 4B][minor_version 4B][...]
  if (
    bytes.length >= 12 &&
    bytes[4] === 0x66 && bytes[5] === 0x74 && bytes[6] === 0x79 && bytes[7] === 0x70
  ) {
    const brand = String.fromCharCode(bytes[8], bytes[9], bytes[10], bytes[11]);
    const heicBrands = ["heic", "heix", "hevc", "hevx", "mif1", "msf1", "MiHE", "MiHA"];
    if (heicBrands.some((b) => brand === b || brand.startsWith(b.substring(0, 4)))) {
      return "heic";
    }
    // MP4/MOV/M4A brands
    return "mp4";
  }
  return "bin";
}

function mimeFromExt(ext: string): string {
  const map: Record<string, string> = {
    jpg: "image/jpeg",
    png: "image/png",
    pdf: "application/pdf",
    mp4: "video/mp4",
    webp: "image/webp",
    heic: "image/heic",
    bin: "application/octet-stream",
  };
  return map[ext] ?? "application/octet-stream";
}

async function sendMessage(botToken: string, chatId: number, text: string): Promise<void> {
  try {
    await fetch(`${TELEGRAM_API}${botToken}/sendMessage`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ chat_id: chatId, text }),
    });
  } catch {
    // Fire-and-forget — sendMessage failure never blocks evidence processing.
  }
}

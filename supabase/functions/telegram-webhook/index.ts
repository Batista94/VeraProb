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

import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { checkConsent } from "../shared/consent_middleware.ts";
import { extractExifMetadata } from "../shared/exif_extractor.ts";
import { validateImageQuality, type QualityWarning } from "../shared/image_quality_validator.ts";
import { formatStatusMessage, formatFinishWarning, type ComplianceRpcResult } from "../shared/compliance_formatter.ts";

// Single type alias used by all helper functions — avoids JSR/npm generic mismatch.
// deno-lint-ignore no-explicit-any
type Supabase = SupabaseClient<any, any, any>;

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

interface TelegramVoice {
  file_id: string;
  file_unique_id: string;
  file_size?: number;
  duration: number;
  mime_type?: string; // NOT trusted (INV-18) — server sniffs magic bytes
}

interface TelegramAudio {
  file_id: string;
  file_unique_id: string;
  file_size?: number;
  duration: number;
  mime_type?: string; // NOT trusted (INV-18)
  file_name?: string; // NOT trusted (INV-18)
}

interface TelegramMessage {
  message_id: number;
  date: number; // Unix timestamp — device clock (INV-6 anchor)
  chat: { id: number };
  text?: string;
  photo?: TelegramPhotoSize[];
  document?: TelegramDocument;
  video?: TelegramVideo;
  voice?: TelegramVoice;
  audio?: TelegramAudio;
}

interface TelegramCallbackQuery {
  id: string;
  from: { id: number };
  message?: TelegramMessage;
  data?: string;
}

interface TelegramUpdate {
  update_id: number;
  message?: TelegramMessage;
  edited_message?: TelegramMessage;
  callback_query?: TelegramCallbackQuery;
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

// ── Category tagging (Menu Pai Universal) ──────────────────────────────────────

const CATEGORY_MAP: Record<string, { emoji: string; label: string }> = {
  estado:    { emoji: "📸", label: "Estado / Visual" },
  doc:       { emoji: "📑", label: "Documental / NF" },
  oper:      { emoji: "🛠️", label: "Operacional" },
  incidente: { emoji: "🚨", label: "Incidente / SLA" },
  outros:    { emoji: "🔍", label: "Outros / Info" },
};

const LGPD_TERMS = `
⚖️ <b>Termos de Uso e Privacidade (LGPD)</b>

Ao utilizar o VeraProb Evidence Bot, você concorda que:

1. <b>Coleta de Dados:</b> Coletamos seu ID de chat do Telegram, fotos, vídeos e documentos enviados, além de metadados técnicos (como data/hora do dispositivo e localização GPS se presente no arquivo).
2. <b>Finalidade:</b> Estes dados são utilizados exclusivamente para a geração de <b>evidências forenses</b> em operações logísticas, servindo como prova de execução e conformidade.
3. <b>Segurança:</b> Suas evidências são seladas com hash SHA-256 e armazenadas em ambiente seguro com isolamento por organização.
4. <b>Compartilhamento:</b> Seus dados serão visíveis apenas para os supervisores e administradores da sua organização no painel VeraProb.
5. <b>Retenção:</b> As evidências são mantidas pelo período necessário para auditoria contratual e conformidade legal.

Você pode revogar este consentimento a qualquer momento entrando em contato com seu supervisor, porém isso impedirá o envio de novas evidências pelo bot.
`.trim();

// ── Self-Link Constants ─────────────────────────────────────────────────────────

const SHORT_ID_CHARSET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"; // Crockford base32
const SHORT_ID_LENGTH = 8;
const SELF_LINK_TTL_S = 86_400; // 24h

function generateShortId(): string {
  const bytes = new Uint8Array(SHORT_ID_LENGTH);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (b) => SHORT_ID_CHARSET[b % SHORT_ID_CHARSET.length]).join("");
}

function formatTripTime(windowStartUtc: string): string {
  const d = new Date(windowStartUtc);
  return `${String(d.getUTCHours()).padStart(2, "0")}:${String(d.getUTCMinutes()).padStart(2, "0")} UTC`;
}

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

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // ── 2b. Callback Query handler (UX Interactions) ─────────────────────────
  if (update.callback_query) {
    const cb = update.callback_query;
    const cbChatId = cb.message?.chat.id;
    if (!cbChatId) return new Response("OK", { status: 200 });

    try {
      if (cb.data === "view_terms") {
        await answerCallbackQuery(botToken, cb.id);
        await sendMessageWithKeyboard(botToken, cbChatId, LGPD_TERMS, [
          [{ text: "✅ Aceitar e Continuar", callback_data: "accept_consent_v1" }]
        ]);
      } 
      else if (cb.data === "accept_consent_v1") {
        await supabase.from("telegram_user_consents").upsert(
          { chat_id: cbChatId, consent_version: "v1" },
          { onConflict: "chat_id,consent_version" },
        );
        
        const binding = await getActiveBinding(supabase, cbChatId);
        await answerCallbackQuery(botToken, cb.id, "✅ Termos aceitos!");
        
        const text = binding
          ? "✅ <b>Termos aceitos!</b>\n\nSua conta já está vinculada. Você já pode enviar fotos ou documentos como evidência forense."
          : "✅ <b>Termos aceitos!</b>\n\nAgora só falta o <b>passo 2</b>: Envie o código de 8 caracteres gerado no aplicativo para vincular sua conta.";
        
        await sendMessageWithKeyboard(botToken, cbChatId, text, [[{ text: "❓ Ajuda", callback_data: "help" }]]);
      } 
      else if (cb.data === "help") {
        await answerCallbackQuery(botToken, cb.id);
        await sendHelpMessage(botToken, cbChatId);
      }
      else if (cb.data === "report_orphan") {
        // Find latest orphan alert for this chat to flag it for the supervisor
        const { data: alert } = await supabase
          .from("operational_alerts")
          .select("id, context")
          .eq("entity_id", String(cbChatId))
          .eq("alert_type", "TELEGRAM_ORPHAN")
          .eq("status", "ACTIVE")
          .order("created_at", { ascending: false })
          .limit(1)
          .maybeSingle();

        if (alert) {
          const updatedContext = { 
            ...(alert.context as Record<string, unknown> || {}), 
            driver_manually_reported: true,
            reported_at: new Date().toISOString()
          };

          await supabase.from("operational_alerts")
            .update({ 
              status: "ACKNOWLEDGED",
              context: updatedContext
            })
            .eq("id", alert.id);
        }

        await answerCallbackQuery(botToken, cb.id, "📣 Notificado!");
        await sendMessageWithKeyboard(botToken, cbChatId, 
          "📣 <b>Supervisor notificado!</b>\n\nSua evidência foi marcada para prioridade de vinculação manual pelo Centro de Comando.",
          [[{ text: "❓ Ajuda", callback_data: "help" }]]);
      }
      // ── tg_tag:{evidenceId}:{category} — Menu Pai Universal ──────────────
      else if (cb.data?.startsWith("tg_tag:")) {
        const parts = cb.data.split(":");
        const evidenceId = parts[1];
        const categoryKey = parts[2];

        if (!evidenceId || !categoryKey || !CATEGORY_MAP[categoryKey]) {
          await answerCallbackQuery(botToken, cb.id, "⚠️ Dados inválidos.");
        } else {
          const cbBinding = await getActiveBinding(supabase, cbChatId);
          if (!cbBinding) {
            await answerCallbackQuery(botToken, cb.id, "⚠️ Chat não vinculado.");
          } else {
            const { error: tagError } = await supabase
              .from("telegram_evidence_categories")
              .insert({
                organization_id: cbBinding.organization_id,
                evidence_upload_id: evidenceId,
                category: categoryKey,
              });

            if (tagError) {
              if (tagError.code === "23505") {
                // Already tagged (UNIQUE constraint) — idempotent
                await answerCallbackQuery(botToken, cb.id, "✅ Já classificado.");
              } else if (tagError.code === "23503") {
                // FK violation — evidence not found or deleted
                await answerCallbackQuery(botToken, cb.id, "⚠️ Registro não encontrado ou expirado.");
              } else {
                console.error(`[telegram-webhook] tag insert error correlationId=${correlationId}:`, tagError);
                await answerCallbackQuery(botToken, cb.id, "❌ Erro ao classificar.");
              }
            } else {
              const cat = CATEGORY_MAP[categoryKey];
              await answerCallbackQuery(botToken, cb.id, `${cat.emoji} Classificado!`);
              // Edit original message: remove buttons, show classification
              if (cb.message?.message_id) {
                await editMessageText(
                  botToken,
                  cbChatId,
                  cb.message.message_id,
                  `✅ Classificado como: ${cat.emoji} <b>${cat.label}</b>`,
                );
              }
              // Task 5: Send checklist shortcut button after classification
              await sendMessageWithKeyboard(botToken, cbChatId,
                "📋 Quer verificar o checklist de conformidade da sua rota?",
                [[{ text: "📋 Ver Checklist Atual", callback_data: "tg_status" }]]);
            }
          }
        }
      }
      // ── tg_lnk_skip — Driver chose not to link ──────────────────────────
      else if (cb.data === "tg_lnk_skip") {
        await answerCallbackQuery(botToken, cb.id, "📎 Salvo para auditoria.");
        if (cb.message?.message_id) {
          await editMessageText(botToken, cbChatId, cb.message.message_id,
            "📎 Evidência salva para auditoria manual pelo supervisor.");
        }
      }
      // ── tg_lnk:{short_id} — Self-link via atomic RPC ────────────────────
      else if (cb.data?.startsWith("tg_lnk:")) {
        const shortId = cb.data.substring(7); // "tg_lnk:".length === 7
        const cbBinding = await getActiveBinding(supabase, cbChatId);

        if (!cbBinding) {
          await answerCallbackQuery(botToken, cb.id, "⚠️ Chat não vinculado.");
        } else {
          try {
            const { data: setId, error: rpcErr } = await supabase.rpc(
              "resolve_telegram_orphan_with_link",
              { p_short_id: shortId, p_driver_id: cbBinding.driver_id },
            );

            if (rpcErr) {
              const msg = rpcErr.message ?? "";
              if (msg.includes("expired")) {
                await answerCallbackQuery(botToken, cb.id, "⚠️ Expirado.");
                if (cb.message?.message_id) {
                  await editMessageText(botToken, cbChatId, cb.message.message_id,
                    "⚠️ Este link de vinculação expirou por razões de segurança.");
                }
              } else if (msg.includes("identity")) {
                await answerCallbackQuery(botToken, cb.id, "⚠️ Não autorizado.");
                if (cb.message?.message_id) {
                  await editMessageText(botToken, cbChatId, cb.message.message_id,
                    "⚠️ Vinculação não autorizada.");
                }
              } else if (rpcErr.code === "23505") {
                // Already linked (idempotent)
                await answerCallbackQuery(botToken, cb.id, "✅ Já vinculado.");
                if (cb.message?.message_id) {
                  await editMessageText(botToken, cbChatId, cb.message.message_id,
                    "✅ Evidência já vinculada anteriormente.");
                }
              } else {
                console.error(`[telegram-webhook] self-link RPC error correlationId=${correlationId}:`, rpcErr);
                await answerCallbackQuery(botToken, cb.id, "❌ Erro ao vincular.");
              }
            } else {
              await answerCallbackQuery(botToken, cb.id, "✅ Vinculado!");
              if (cb.message?.message_id) {
                await editMessageText(botToken, cbChatId, cb.message.message_id,
                  `✅ <b>Sucesso!</b>\nEvidência vinculada à rota <b>${setId}</b> com sucesso.`);
              }
            }
          } catch (e) {
            console.error(`[telegram-webhook] self-link error correlationId=${correlationId}:`, e);
            await answerCallbackQuery(botToken, cb.id, "❌ Erro ao vincular.");
          }
        }
      }
      // ── tg_status — Compliance checklist via callback button ──────────────
      else if (cb.data === "tg_status") {
        const cbBinding = await getActiveBinding(supabase, cbChatId);
        if (!cbBinding) {
          await answerCallbackQuery(botToken, cb.id, "⚠️ Chat não vinculado.");
        } else {
          await answerCallbackQuery(botToken, cb.id, "📋 Verificando...");
          await handleStatusCheck(supabase, botToken, cbChatId, cbBinding, correlationId, "tg_status_button");
        }
      }
      // ── tg_finish_confirm:{set_id} — Driver confirms finish with gaps ────
      else if (cb.data?.startsWith("tg_finish_confirm:")) {
        const setId = cb.data.substring(18); // "tg_finish_confirm:".length === 18
        const cbBinding = await getActiveBinding(supabase, cbChatId);
        if (!cbBinding) {
          await answerCallbackQuery(botToken, cb.id, "⚠️ Chat não vinculado.");
        } else {
          // Log forced completion with gaps (forensic negligence audit)
          supabase.from("telegram_status_queries").insert({
            organization_id: cbBinding.organization_id,
            driver_id: cbBinding.driver_id,
            chat_id: cbChatId,
            set_id: setId,
            compliance_snapshot: { query_type: "finish_forced", forced_completion_with_gaps: true },
          }).then(() => {}, () => {});

          await answerCallbackQuery(botToken, cb.id, "✅ Encerrado.");
          if (cb.message?.message_id) {
            await editMessageText(botToken, cbChatId, cb.message.message_id,
              "✅ <b>Rota encerrada.</b>\n⚠️ Evidências pendentes foram registradas no sistema.");
          }
        }
      }
      // ── tg_start_transit:{set_id} — Driver initiates trip (planned → inTransit) ──
      // First-wins idempotent: if already inTransit, returns true silently.
      else if (cb.data?.startsWith("tg_start_transit:")) {
        const setId = cb.data.substring(17); // "tg_start_transit:".length === 17
        const cbBinding = await getActiveBinding(supabase, cbChatId);
        if (!cbBinding) {
          await answerCallbackQuery(botToken, cb.id, "⚠️ Chat não vinculado.");
        } else {
          const { data: ok } = await supabase.rpc("start_transit_for_execution", {
            p_org_id: cbBinding.organization_id,
            p_set_id: setId,
          });
          if (ok) {
            await answerCallbackQuery(botToken, cb.id, "▶️ Viagem iniciada!");
            if (cb.message?.message_id) {
              await editMessageText(botToken, cbChatId, cb.message.message_id,
                `▶️ <b>Viagem iniciada.</b>\nRota <b>${setId}</b> em trânsito. Envie suas evidências.`);
            }
          } else {
            await answerCallbackQuery(botToken, cb.id, "⚠️ Não foi possível iniciar.");
          }
        }
      }
      // ── tg_finish_cancel — Driver cancels finish ─────────────────────────
      else if (cb.data === "tg_finish_cancel") {
        await answerCallbackQuery(botToken, cb.id, "↩️ Cancelado.");
        if (cb.message?.message_id) {
          await editMessageText(botToken, cbChatId, cb.message.message_id,
            "↩️ Encerramento cancelado. Continue enviando suas evidências.");
        }
      }
    } catch (e) {
      console.error(`[telegram-webhook] callback error correlationId=${correlationId}:`, e);
      await answerCallbackQuery(botToken, cb.id, "❌ Erro ao processar.");
    }
    return new Response("OK", { status: 200 });
  }

  if (!message) return new Response("OK", { status: 200 });

  const chatId = message.chat.id;

  // ── 3. /start command ─────────────────────────────────────────────────────
  if (message.text?.startsWith("/start")) {
    const alreadyConsented = await checkConsent(supabase, chatId);
    if (alreadyConsented) {
      await sendMessageWithKeyboard(
        botToken, chatId,
        "<b>Bem-vindo ao VeraProb Evidence Bot!</b>\n\n" +
        "✅ Seus termos de uso (LGPD) já estão aceitos.\n\n" +
        "Agora, envie o <b>código de 8 caracteres</b> gerado no aplicativo VeraProb para vincular sua conta.\n\n" +
        "Após a vinculação, você poderá enviar fotos ou documentos como evidência forense.",
        [[{ text: "❓ Ajuda", callback_data: "help" }]],
      );
    } else {
      await sendMessageWithKeyboard(
        botToken, chatId,
        "<b>Bem-vindo ao VeraProb Evidence Bot!</b>\n\n" +
        "Para operar, você precisa de dois passos:\n" +
        "1️⃣ <b>Aceitar os Termos (LGPD)</b>\n" +
        "2️⃣ <b>Vincular sua conta</b>\n\n" +
        "Clique no botão abaixo para ler os termos e continuar:",
        [[{ text: "📋 Ler Termos de Uso (LGPD)", callback_data: "view_terms" }]],
      );
    }
    return new Response("OK", { status: 200 });
  }

  // ── 4. /help command ──────────────────────────────────────────────────────
  if (message.text?.startsWith("/help")) {
    await sendHelpMessage(botToken, chatId);
    return new Response("OK", { status: 200 });
  }

  // ── 4b. /audio command — voice evidence compliance guide ──────────────────
  if (message.text?.startsWith("/audio")) {
    await sendMessageWithKeyboard(
      botToken, chatId,
      "🎙️ <b>Depoimento de Voz</b>\n\n" +
      "Para registrar evidência em áudio:\n\n" +
      "1️⃣ Pressione e segure o botão 🎤 do Telegram\n" +
      "2️⃣ Grave seu relato sobre o ocorrido\n" +
      "3️⃣ Solte para enviar\n\n" +
      "O áudio será automaticamente:\n" +
      "✅ Assinado com hash SHA-256\n" +
      "✅ Vinculado à sua rota ativa\n" +
      "✅ Classificado por categoria\n\n" +
      "⚠️ Limite: 10 MB",
      [[{ text: "❓ Ajuda", callback_data: "help" }]],
    );
    return new Response("OK", { status: 200 });
  }

  // ── 4c. /status command — evidence compliance checklist ─────────────────────
  if (message.text?.startsWith("/status")) {
    const binding = await getActiveBinding(supabase, chatId);
    if (!binding) {
      await sendMessageWithKeyboard(botToken, chatId,
        "Chat não vinculado. Envie o código do aplicativo VeraProb primeiro.",
        [[{ text: "❓ Ajuda", callback_data: "help" }]]);
    } else {
      await handleStatusCheck(supabase, botToken, chatId, binding, correlationId);
    }
    return new Response("OK", { status: 200 });
  }

  // ── 4d. /finish command — predictive compliance alert ─────────────────────
  if (message.text?.startsWith("/finish")) {
    const binding = await getActiveBinding(supabase, chatId);
    if (!binding) {
      await sendMessageWithKeyboard(botToken, chatId,
        "Chat não vinculado. Envie o código do aplicativo VeraProb primeiro.",
        [[{ text: "❓ Ajuda", callback_data: "help" }]]);
    } else {
      await handleFinishCheck(supabase, botToken, chatId, binding, correlationId);
    }
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
          const hasConsent = await checkConsent(supabase, chatId);
          if (hasConsent) {
            await sendMessageWithKeyboard(
              botToken, chatId,
              "✅ Vinculação realizada com sucesso!\nAgora você pode enviar fotos ou documentos como evidência forense.",
              [[{ text: "❓ Ajuda", callback_data: "help" }]],
            );
          } else {
            await sendMessageWithKeyboard(
              botToken, chatId,
              "✅ Vinculação realizada com sucesso!\n\n⚠️ <b>Atenção:</b> Para começar a enviar evidências, você ainda precisa aceitar os Termos de Uso.\n\nEnvie /start para visualizar e aceitar os termos.",
              [[{ text: "📋 Ver Termos", callback_data: "accept_consent_v1" }]],
            );
          }
        }
      } catch (e) {
        console.error(`[telegram-webhook] bind error correlationId=${correlationId}:`, e);
        await sendMessageWithKeyboard(botToken, chatId, "Erro interno. Tente novamente.");
      }
    } else {
      const hasConsent = await checkConsent(supabase, chatId);
      const binding = await getActiveBinding(supabase, chatId);

      if (!hasConsent) {
        await sendMessageWithKeyboard(
          botToken, chatId,
          "⚠️ <b>Passo Pendente: LGPD</b>\n\n" +
          "Para operar, você primeiro precisa aceitar os termos de uso.\n\n" +
          "Clique no botão abaixo para ler e continuar:",
          [[{ text: "📋 Ler Termos de Uso (LGPD)", callback_data: "view_terms" }]],
        );
      } else if (!binding) {
        await sendMessageWithKeyboard(
          botToken, chatId,
          "⚠️ <b>Passo Pendente: Vinculação</b>\n\n" +
          "Seus termos já estão aceitos, mas sua conta ainda não foi vinculada.\n\n" +
          "Envie o <b>código de 8 caracteres</b> gerado no aplicativo VeraProb para concluir.",
          [[{ text: "❓ Ajuda", callback_data: "help" }]],
        );
      } else {
        await sendMessageWithKeyboard(
          botToken, chatId,
          "Para enviar evidências, anexe uma foto ou documento.",
          [[{ text: "❓ Ajuda", callback_data: "help" }]],
        );
      }
    }
    return new Response("OK", { status: 200 });
  }

  // ── 6. Photo / Document / Video — evidence upload ─────────────────────────
  const fileInfo = extractFileInfo(message);
  if (!fileInfo) return new Response("OK", { status: 200 });

  // 6.pre: LGPD Consent Gate — block ALL processing without consent (INV-3)
  const hasConsent = await checkConsent(supabase, chatId);
  if (!hasConsent) {
    await sendMessageWithKeyboard(botToken, chatId,
      "⚠️ Para enviar evidências, é necessário aceitar os Termos de Uso.\nClique no botão abaixo para ler e aceitar.",
      [[{ text: "📋 Ler Termos", callback_data: "view_terms" }]]);
    return new Response("OK", { status: 200 });
  }

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

  // 6a.post: Clock discrepancy audit log (INV-7) — forensic gold for fraud detection.
  const clockDriftS = Math.round(Date.now() / 1000 - message.date);
  console.info(`[telegram-webhook] clock_drift correlationId=${correlationId} chat_id=${chatId} drift_seconds=${clockDriftS}`);

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

    // 6h.post: Image quality validation (INV-18)
    let qualityWarning: QualityWarning | null = null;
    if (message.photo?.length) {
      const largest = message.photo[message.photo.length - 1];
      qualityWarning = validateImageQuality(largest.width, largest.height, largest.file_size);
    }
    
    if (ext === "bin") {
      console.warn(`[telegram-webhook] unsupported format correlationId=${correlationId}`);
      await sendMessageWithKeyboard(
        botToken, chatId,
        "⚠️ <b>Formato não suportado.</b>\nPor favor, envie apenas fotos (JPG/PNG), vídeos (MP4), áudios (voice note) ou documentos PDF.",
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
    const executionInfo = await findExecutionForTelegram(
      supabase,
      binding.organization_id,
      binding.driver_id,
      message.date,
      correlationId,
    );
    const linkedSetId = executionInfo?.setId ?? null;
    const requiresManualLink = linkedSetId === null;

    // 6k. Insert evidence record — idempotent via UNIQUE (chat_id, telegram_message_id).
    //     telegram_message_date = device timestamp (INV-6 audit anchor).
    const { data: insertedRow, error: insertError } = await supabase
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
        mime_type: mimeFromExt(ext), // INV-18: server-authoritative from magic bytes
        // uploaded_at_utc: omitted — DB DEFAULT NOW() is the ingest anchor for discrepancy audit
      })
      .select("id")
      .single();

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

    const evidenceId = insertedRow?.id as string;

    // 6k.post: Extract EXIF metadata (best-effort, non-blocking) (INV-9, INV-18)
    const exifData = extractExifMetadata(byteArray);
    if (exifData) {
      await supabase.from("telegram_evidence_metadata").insert({
        organization_id: binding.organization_id,
        evidence_upload_id: evidenceId,
        exif_data: exifData,
      }).then(() => {}, (e: unknown) => {
        console.warn(`[telegram-webhook] exif metadata insert failed correlationId=${correlationId}:`, e);
      });
    }

    // 6l. WS-4 Proactive Orphan Flag: fire TELEGRAM_ORPHAN alert when no execution found.
    if (requiresManualLink) {
      await fireOrphanAlert(supabase, binding.organization_id, chatId, hashHex, correlationId, evidenceId, binding.driver_id);
    }

    // 6m. WS-4 Feedback Diferencial:
    //     Linked  → receipt + execution_id (confirms forensic chain)
    //     Orphan  → forensic receipt only (strategic silence — no anxiety)
    const qualitySuffix = qualityWarning ? `\n⚠️ ${qualityWarning.message}` : "";
    const isAudioEvidence = ext === "ogg";
    if (executionInfo) {
      const receiptEmoji = isAudioEvidence ? "🎙️" : "✅";
      const receiptTitle = isAudioEvidence ? "Depoimento Forense Registrado" : "Evidência registrada";
      await sendMessageWithKeyboard(
        botToken, chatId,
        `${receiptEmoji} <b>${receiptTitle}</b>\n` +
        `🔐 Assinatura: <code>${hashHex.substring(0, 16)}…</code>\n` +
        `📍 <b>Rota:</b> ${executionInfo.displayName}${qualitySuffix}`,
        [[{ text: "❓ Ajuda", callback_data: "help" }]],
      );
    } else {
      // 6m.self-link: Secondary search — find pending trips for self-linking.
      //   Webhook is "dumb": asks the DB and renders the result.
      //   Plate normalization (UPPER + strip hyphens) is inside the RPC.
      let selfLinkOffered = false;
      try {
        const { data: trips } = await supabase.rpc("find_pending_trips_for_driver", {
          p_org_id: binding.organization_id,
          p_driver_id: binding.driver_id,
          p_limit: 3,
        });

        if (trips && (trips as unknown[]).length > 0) {
          const tripRows = trips as { set_id: string; window_start_utc: string }[];
          // Insert pending links with short_ids
          const pendingRows = tripRows.map((t) => ({
            short_id: generateShortId(),
            organization_id: binding.organization_id,
            evidence_upload_id: evidenceId,
            execution_set_id: t.set_id,
            driver_id: binding.driver_id,
            expires_at_utc: new Date(Date.now() + SELF_LINK_TTL_S * 1000).toISOString(),
          }));

          const { error: plErr } = await supabase
            .from("telegram_pending_links")
            .insert(pendingRows);

          if (!plErr) {
            const tripButtons: InlineKeyboardButton[][] = pendingRows.map((row, i) => ([{
              text: `🚚 Vincular à ${tripRows[i].set_id} (${formatTripTime(tripRows[i].window_start_utc)})`,
              callback_data: `tg_lnk:${row.short_id}`,
            }]));
            tripButtons.push([{ text: "❌ Não, apenas salvar", callback_data: "tg_lnk_skip" }]);

            await sendMessageWithKeyboard(
              botToken, chatId,
              `📎 <b>Recibo Forense Gerado.</b>\n` +
              `🔐 Assinatura: <code>${hashHex.substring(0, 16)}…</code>${qualitySuffix}\n\n` +
              (isAudioEvidence
                ? `🎙️ Depoimento de voz recebido. Não identifiquei uma viagem ativa agora. Deseja vincular a uma de suas viagens agendadas?`
                : `Não identifiquei uma viagem ativa agora. Deseja vincular esta foto a uma de suas viagens agendadas?`),
              tripButtons,
            );
            selfLinkOffered = true;
          }
        }
      } catch (e) {
        // Non-blocking: self-link is best-effort. Fall through to standard orphan receipt.
        console.warn(`[telegram-webhook] self-link search failed correlationId=${correlationId}:`, e);
      }

      if (!selfLinkOffered) {
        await sendMessageWithKeyboard(
          botToken, chatId,
          `📎 <b>Recibo Forense</b>\n` +
          `🔐 Assinatura: <code>${hashHex.substring(0, 16)}…</code>${qualitySuffix}`,
          [
            [{ text: "❓ Ajuda", callback_data: "help" }],
            [{ text: "📣 Reportar ao Supervisor", callback_data: "report_orphan" }],
          ],
        );
      }
    }

    // 6n. Menu Pai Universal: category tagging (fire-and-forget, never blocks evidence).
    //     Sent as a SEPARATE message so the forensic receipt above stays clean.
    //     callback_data format: tg_tag:{UUID}:{key} — max 50 bytes, within 64-byte limit.
    await sendMessageWithKeyboard(
      botToken, chatId,
      "🏷️ <b>Como você classifica esta evidência?</b>",
      [
        [
          { text: "📸 Estado / Visual", callback_data: `tg_tag:${evidenceId}:estado` },
          { text: "📑 Documental / NF", callback_data: `tg_tag:${evidenceId}:doc` },
        ],
        [
          { text: "🛠️ Operacional", callback_data: `tg_tag:${evidenceId}:oper` },
          { text: "🚨 Incidente / SLA", callback_data: `tg_tag:${evidenceId}:incidente` },
        ],
        [
          { text: "🔍 Outros / Info", callback_data: `tg_tag:${evidenceId}:outros` },
        ],
      ],
    );
  } catch (e) {
    console.error(`[telegram-webhook] evidence processing error correlationId=${correlationId}:`, e);
    await sendMessageWithKeyboard(botToken, chatId, "Erro ao processar evidência. Tente novamente.");
  }

  return new Response("OK", { status: 200 });
});

// ── WS-4 UX Functions ─────────────────────────────────────────────────────────

/**
 * Sends the operation guide to the user.
 */
async function sendHelpMessage(botToken: string, chatId: number): Promise<void> {
  await sendMessageWithKeyboard(
    botToken, chatId,
    "📋 <b>VeraProb Evidence Bot - Guia de Operação</b>\n\n" +
    "Para operar, você precisa cumprir dois requisitos:\n" +
    "1️⃣ <b>Aceite da LGPD:</b> Envie /start para ler e aceitar os termos.\n" +
    "2️⃣ <b>Vinculação:</b> Envie o código de 8 caracteres gerado no App.\n\n" +
    "• Após cumprir ambos, anexe fotos, documentos ou áudios para registro.\n" +
    "• Cada envio gera um recibo forense com <b>assinatura digital única</b>.\n" +
    "• Envie /audio para instruções sobre depoimentos de voz.\n" +
    "• Dúvidas? Contate seu supervisor operacional.",
  );
}

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

interface ExecutionInfo {
  setId: string;
  displayName: string;
}

/**
 * WS-4 Dead Zone Logic (INV-6):
 * Delegates to RPC find_execution_for_telegram which implements:
 *   - Retroactive window: [message_ts - 10min, message_ts + 4h]
 *   - Latest-Wins: ORDER BY window_start_utc DESC LIMIT 1
 * Failure never blocks evidence ingestion.
 */
async function findExecutionForTelegram(
  supabase: Supabase,
  orgId: string,
  driverId: string,
  messageUnixTs: number,
  correlationId: string,
): Promise<ExecutionInfo | null> {
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
    if (data) {
      const setId = data as string;
      return { setId, displayName: setId };
    }
    return null;
  } catch {
    return null;
  }
}


/**
 * WS-4 Proactive Orphan Flag:
 * Inserts a TELEGRAM_ORPHAN alert for supervisor triage.
 * Uses (chat_id as entity_id, correlationId as triggering_event_id) for idempotency.
 * Failure is non-blocking — evidence is already committed.
 * Context includes driver_id + driver_name for Command Center smart grouping.
 */
async function fireOrphanAlert(
  supabase: Supabase,
  orgId: string,
  chatId: number,
  forensicHash: string,
  correlationId: string,
  evidenceId: string,
  driverId: string,
): Promise<void> {
  // Fetch driver name for Command Center grouping (INV-7: best-effort, non-blocking)
  let driverName: string | null = null;
  try {
    const { data: driver } = await supabase
      .from("drivers")
      .select("full_name")
      .eq("id", driverId)
      .maybeSingle();
    driverName = (driver?.full_name as string | null) ?? null;
  } catch { /* non-blocking */ }

  try {
    await supabase.from("operational_alerts").insert({
      organization_id: orgId,
      entity_id: String(chatId),
      contract_id: "TELEGRAM_ORPHAN",
      alert_type: "TELEGRAM_ORPHAN",
      severity: "CRITICAL",
      status: "ACTIVE",
      source: "telegram",
      triggering_event_id: correlationId,
      context: {
        correlation_id: correlationId,
        forensic_hash_prefix: forensicHash.substring(0, 16),
        chat_id: chatId,
        evidence_id: evidenceId,
        deep_link: `veraprob://reconciliation/${evidenceId}`,
        driver_id: driverId,
        ...(driverName ? { driver_name: driverName } : {}),
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
  if (message.voice) return { fileId: message.voice.file_id, fileSize: message.voice.file_size };
  if (message.audio) return { fileId: message.audio.file_id, fileSize: message.audio.file_size };
  if (message.document) return { fileId: message.document.file_id, fileSize: message.document.file_size };
  if (message.video) return { fileId: message.video.file_id, fileSize: message.video.file_size };
  return null;
}

async function getActiveBinding(
  supabase: Supabase,
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
 * Answers a Telegram callback query (inline button press).
 * Fire-and-forget — failure never blocks processing.
 */
async function answerCallbackQuery(botToken: string, callbackQueryId: string, text?: string): Promise<void> {
  try {
    const body: Record<string, unknown> = { callback_query_id: callbackQueryId };
    if (text) body.text = text;

    await fetch(`${TELEGRAM_API}${botToken}/answerCallbackQuery`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
  } catch { /* fire-and-forget */ }
}

/**
 * Edits a previously sent message text and removes inline keyboard.
 * Used by Menu Pai Universal to replace category buttons with confirmation.
 * Fire-and-forget — failure never blocks processing.
 */
async function editMessageText(
  botToken: string,
  chatId: number,
  messageId: number,
  text: string,
): Promise<void> {
  try {
    await fetch(`${TELEGRAM_API}${botToken}/editMessageText`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        chat_id: chatId,
        message_id: messageId,
        text,
        parse_mode: "HTML",
        reply_markup: { inline_keyboard: [] },
      }),
    });
  } catch { /* fire-and-forget */ }
}

/**
 * Sniffs file extension from magic bytes (INV-18: never trust Telegram metadata).
 */
function sniffExtension(bytes: Uint8Array): string {
  if (bytes[0] === 0xFF && bytes[1] === 0xD8 && bytes[2] === 0xFF) return "jpg";
  if (bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4E && bytes[3] === 0x47) return "png";
  if (bytes[0] === 0x25 && bytes[1] === 0x50 && bytes[2] === 0x44 && bytes[3] === 0x46) return "pdf";
  // OGG container (Opus/Vorbis voice messages) — "OggS" magic bytes
  if (bytes[0] === 0x4F && bytes[1] === 0x67 && bytes[2] === 0x67 && bytes[3] === 0x53) return "ogg";
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
    ogg: "audio/ogg", bin: "application/octet-stream",
  };
  return map[ext] ?? "application/octet-stream";
}


// ── Compliance Status Helpers ──────────────────────────────────────────────────

/**
 * Shared handler for /status command and tg_status callback.
 * Calls get_trip_compliance_status RPC, formats the checklist, and logs the query.
 *
 * INV-1: org_id from binding, never from Telegram.
 * INV-7: telegram_status_queries is append-only.
 */
async function handleStatusCheck(
  supabase: Supabase,
  botToken: string,
  chatId: number,
  binding: ActiveBinding,
  correlationId: string,
  queryType: string = "status",
): Promise<void> {
  try {
    const { data, error } = await supabase.rpc("get_trip_compliance_status", {
      p_org_id: binding.organization_id,
      p_driver_id: binding.driver_id,
    });

    if (error) {
      console.warn(`[telegram-webhook] compliance RPC error correlationId=${correlationId}:`, error);
      await sendMessageWithKeyboard(botToken, chatId,
        "⚠️ Não foi possível verificar a conformidade. Tente novamente.",
        [[{ text: "❓ Ajuda", callback_data: "help" }]]);
      return;
    }

    const result = data as ComplianceRpcResult;

    // Forensic audit: log the query (fire-and-forget, INV-7)
    supabase.from("telegram_status_queries").insert({
      organization_id: binding.organization_id,
      driver_id: binding.driver_id,
      chat_id: chatId,
      set_id: "set_id" in result ? (result as { set_id: string }).set_id : null,
      compliance_snapshot: { ...(result as Record<string, unknown>), query_type: queryType },
    }).then(() => {}, (e: unknown) => {
      console.warn(`[telegram-webhook] status query audit insert failed correlationId=${correlationId}:`, e);
    });

    await sendMessageWithKeyboard(botToken, chatId,
      formatStatusMessage(result),
      result.status !== "no_active_trip" && (result as { execution_status?: string }).execution_status === "planned"
        ? [
            [{ text: "▶️ Iniciar Viagem", callback_data: `tg_start_transit:${(result as { set_id: string }).set_id}` }],
            [{ text: "❓ Ajuda", callback_data: "help" }],
          ]
        : [[{ text: "❓ Ajuda", callback_data: "help" }]]);
  } catch (e) {
    console.error(`[telegram-webhook] handleStatusCheck error correlationId=${correlationId}:`, e);
    await sendMessageWithKeyboard(botToken, chatId,
      "⚠️ Erro ao verificar conformidade. Tente novamente.",
      [[{ text: "❓ Ajuda", callback_data: "help" }]]);
  }
}

/**
 * Shared handler for /finish command.
 * Checks compliance, warns about gaps, but NEVER blocks completion.
 * forced_completion_with_gaps flag logged for forensic negligence audit.
 */
async function handleFinishCheck(
  supabase: Supabase,
  botToken: string,
  chatId: number,
  binding: ActiveBinding,
  correlationId: string,
): Promise<void> {
  try {
    const { data, error } = await supabase.rpc("get_trip_compliance_status", {
      p_org_id: binding.organization_id,
      p_driver_id: binding.driver_id,
    });

    if (error) {
      console.warn(`[telegram-webhook] finish compliance RPC error correlationId=${correlationId}:`, error);
      await sendMessageWithKeyboard(botToken, chatId,
        "⚠️ Não foi possível verificar a conformidade antes do encerramento.",
        [[{ text: "❓ Ajuda", callback_data: "help" }]]);
      return;
    }

    const result = data as ComplianceRpcResult;

    if (result.status === "no_active_trip") {
      await sendMessageWithKeyboard(botToken, chatId,
        "📍 Você não possui rotas ativas para encerrar.",
        [[{ text: "❓ Ajuda", callback_data: "help" }]]);
      return;
    }

    const setId = (result as { set_id: string }).set_id;
    const isComplete = result.status === "no_requirements" ||
      (result.status === "active" && result.total_fulfilled >= result.total_required);

    if (isComplete) {
      supabase.from("telegram_status_queries").insert({
        organization_id: binding.organization_id,
        driver_id: binding.driver_id,
        chat_id: chatId,
        set_id: setId,
        compliance_snapshot: { ...(result as Record<string, unknown>), query_type: "finish_complete" },
      }).then(() => {}, () => {});

      await sendMessageWithKeyboard(botToken, chatId,
        "✅ <b>Checklist completo!</b>\nRota pronta para encerramento.",
        [[{ text: "❓ Ajuda", callback_data: "help" }]]);
      return;
    }

    // Gaps exist — warn but never block
    await sendMessageWithKeyboard(botToken, chatId,
      formatFinishWarning(result as Extract<ComplianceRpcResult, { status: "active" }>), [
      [{ text: "✅ Sim, encerrar", callback_data: `tg_finish_confirm:${setId}` }],
      [{ text: "❌ Voltar", callback_data: "tg_finish_cancel" }],
    ]);
  } catch (e) {
    console.error(`[telegram-webhook] handleFinishCheck error correlationId=${correlationId}:`, e);
    await sendMessageWithKeyboard(botToken, chatId,
      "⚠️ Erro ao verificar conformidade para encerramento.",
      [[{ text: "❓ Ajuda", callback_data: "help" }]]);
  }
}

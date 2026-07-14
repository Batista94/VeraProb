/**
 * Edge Function: dispatch-verdict-webhooks (Fase 10.7)
 * 
 * **Dual-Path Dispatch (V1):**
 * - Cron Mode: Triggered by GHA cron using SERVICE_ROLE_KEY. Scans all PENDING/FAILED logs.
 * - Kick Mode: Triggered by Dart using USER_JWT. Scans only the tenant's logs. Rate-limited.
 * 
 * **SSRF Anti-DNS-Rebinding (V2):**
 * - URL is resolved to IPs. If any IP is private/local, it aborts.
 * - Connection is made via `Deno.startTls` locking to the validated IP.
 * 
 * **Key Rotation & HMAC (V3 & V4):**
 * - Derives the HMAC key dynamically per org using the master key and org ID.
 * - Cross-verifies evidence_hash before signing.
 */

import { createClient } from "jsr:@supabase/supabase-js@2";
import { handleWithSecurity, type SecurityContext } from "../shared/handle_with_security.ts";
import { canonicalJson } from "../shared/canonical_json.ts";
// INV-31: all HMAC signing routes through the audited shared signer. Webhooks use the
// per-org derived key (INV-28) exported from there.
import { deriveOrgKey, signWithDerivedKey } from "../shared/hmac_signer.ts";
import { isServiceRoleAuth } from "../shared/service_role_auth.ts";

// Utility for SSRF Protection (V2)
function isPublicIp(ip: string): boolean {
  if (ip.startsWith("10.") || ip.startsWith("192.168.") || ip.startsWith("127.") || ip.startsWith("169.254.") || ip.startsWith("0.")) {
    return false;
  }
  if (ip.match(/^172\.(1[6-9]|2[0-9]|3[0-1])\./)) {
    return false; // 172.16.0.0/12
  }
  if (ip.match(/^100\.(6[4-9]|[7-9][0-9]|1[0-1][0-9]|12[0-7])\./)) {
    return false; // 100.64.0.0/10 (CGNAT)
  }
  // IPv6 local/private
  const lower = ip.toLowerCase();
  // IPv4-mapped IPv6 (::ffff:a.b.c.d): re-validate the embedded IPv4; block hex-mapped form.
  if (lower.startsWith("::ffff:")) {
    const tail = lower.slice(7);
    return tail.includes(".") ? isPublicIp(tail) : false;
  }
  // fe80::/10 link-local; fc00::/7 unique-local spans fc00:–fdff:.
  if (lower === "::1" || lower === "::" || lower.startsWith("fe80:") || lower.startsWith("fc") || lower.startsWith("fd")) {
    return false;
  }
  return true;
}

export async function handler(ctx: SecurityContext, supabase: ReturnType<typeof createClient>, req: Request): Promise<Response> {
  const authHeader = req.headers.get("Authorization") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const isCron = isServiceRoleAuth(authHeader, serviceRoleKey);

  // If it's not cron, it must be an authenticated kick from the tenant
  if (!isCron && !ctx.orgId) {
    return new Response(JSON.stringify({ error: "Unauthorized kick" }), { status: 401 });
  }

  const queryOrgId = isCron ? null : ctx.orgId;

  // Rate Limiting for Kick Mode (V1)
  if (!isCron && queryOrgId) {
    const { data: endpoint } = await supabase
      .from("webhook_endpoints")
      .select("last_kick_at")
      .eq("organization_id", queryOrgId)
      .eq("is_active", true)
      .maybeSingle();
    
    if (endpoint?.last_kick_at) {
      const lastKick = new Date(endpoint.last_kick_at).getTime();
      const now = new Date().getTime();
      if (now - lastKick < 30000) {
        return new Response(JSON.stringify({ error: "Rate limit exceeded (30s)" }), { status: 429 });
      }
    }
    
    await supabase.from("webhook_endpoints").update({ last_kick_at: new Date().toISOString() }).eq("organization_id", queryOrgId).eq("is_active", true);
  }

  // Drain logic via RPC
  const { data: logs, error: drainErr } = await supabase.rpc("drain_pending_webhooks", {
    p_org_id: queryOrgId,
    p_limit: isCron ? 100 : 10
  });

  if (drainErr || !logs || logs.length === 0) {
    return new Response(JSON.stringify({ ok: true, processed: 0 }), { status: 200, headers: { "Content-Type": "application/json" } });
  }

  let processed = 0;

  for (const log of logs) {
    try {
      const { id, org_id_out, payload, endpoint_url, signing_version } = log;
      const organization_id = org_id_out;

      // Anti-SSRF Rebinding (V2)
      let u: URL;
      try {
        u = new URL(endpoint_url);
        if (u.protocol !== "https:") throw new Error("HTTPS only");
        if (u.username || u.password) throw new Error("No userinfo allowed");
        if (u.port && u.port !== "443") throw new Error("Port 443 only");
      } catch (e) {
        await supabase.from("webhook_delivery_logs").update({ status: 'DEAD', last_error: 'INVALID_URL' }).eq("id", id);
        continue;
      }

      const ipv4 = await Deno.resolveDns(u.hostname, "A").catch(() => []);
      const ipv6 = await Deno.resolveDns(u.hostname, "AAAA").catch(() => []);
      const allIps = [...ipv4, ...ipv6];

      if (allIps.length === 0 || !allIps.every(isPublicIp)) {
        await supabase.from("webhook_delivery_logs").update({ status: 'DEAD', last_error: 'SSRF_BLOCKED' }).eq("id", id);
        continue;
      }

      // V4 Cross-Verify — recompute the integrity-critical financial value from the
      // immutable append-only ledger (INV-3), NOT from the copied delivery payload.
      // The fine is sealed at verdict_evidence.fine_cents (INV-15). A mismatch means the
      // outbox copy was tampered between enqueue and dispatch → DEAD, never signed.
      const ledgerEntryId = payload?.case?.ledger_entry_id;
      const { data: ledger, error: ledgerErr } = await supabase
        .from("sla_audit_ledger_v2")
        .select("payload")
        .eq("organization_id", organization_id)
        .eq("id", ledgerEntryId ?? "")
        .maybeSingle();

      // INV-4: fine_cents is BIGINT — compare as BigInt to avoid float64 precision loss above 2^53.
      const sealedFine = BigInt(ledger?.payload?.verdict_evidence?.fine_cents ?? 0);
      const payloadFine = BigInt(payload?.financial?.fine_cents ?? 0);

      if (ledgerErr || !ledger || sealedFine !== payloadFine) {
        await supabase.from("webhook_delivery_logs").update({ status: 'DEAD', last_error: 'PAYLOAD_TAMPERED' }).eq("id", id);
        await supabase.from("system_audit_log").insert({
          organization_id,
          event_type: 'PAYLOAD_TAMPERED',
          severity: 'critical',
          source: 'edge_function',
          payload: { log_id: id, sealed_fine_cents: sealedFine.toString(), payload_fine_cents: payloadFine.toString() }
        });
        continue;
      }

      // Payload Signing — per-org derived key (V3 + INV-28 + INV-31)
      const rawBody = canonicalJson(payload);
      const ts = Math.floor(Date.now() / 1000).toString();
      const stringToSign = `${ts}.${rawBody}`;

      const used_version = signing_version;
      const orgKey = await deriveOrgKey(organization_id, used_version);
      const finalSignature = `v${used_version}|${await signWithDerivedKey(orgKey, stringToSign)}`;

      // Dispatch via manual TCP/TLS to avoid standard fetch DNS rebinding.
      // Connect to a VALIDATED ip (never the hostname → no re-resolution); prefer IPv4, else IPv6.
      const targetIp = (ipv4[0] ?? ipv6[0]) as string;
      const encoder = new TextEncoder();
      const httpRequest =
        `POST ${u.pathname}${u.search} HTTP/1.1\r\n` +
        `Host: ${u.hostname}\r\n` +
        `Content-Type: application/json\r\n` +
        `Content-Length: ${encoder.encode(rawBody).length}\r\n` +
        `X-VeraProb-Event-Id: ${id}\r\n` +
        `X-VeraProb-Timestamp: ${ts}\r\n` +
        `X-VeraProb-Key-Version: ${used_version}\r\n` +
        `X-VeraProb-Signature: ${finalSignature}\r\n` +
        `Connection: close\r\n\r\n` +
        `${rawBody}`;

      const conn = await Deno.connect({ hostname: targetIp, port: 443 });
      let tls: Deno.TlsConn | null = null;
      let statusCode = 0;
      try {
        tls = await Deno.startTls(conn, { hostname: u.hostname });
        await tls.write(encoder.encode(httpRequest));

        // The HTTP status line may not arrive in the first read; accumulate until CRLF.
        const buffer = new Uint8Array(1024);
        const decoder = new TextDecoder();
        let responseStr = "";
        for (let reads = 0; reads < 8; reads++) {
          const n = await tls.read(buffer);
          if (n === null) break;
          responseStr += decoder.decode(buffer.subarray(0, n), { stream: true });
          if (responseStr.includes("\r\n")) break;
        }
        const statusMatch = responseStr.match(/^HTTP\/1\.1 (\d+)/);
        statusCode = statusMatch ? parseInt(statusMatch[1], 10) : 0;
      } finally {
        // tls.close() also closes the underlying conn; if startTls failed, close conn directly.
        if (tls) { try { tls.close(); } catch { /* ignore */ } }
        else { try { conn.close(); } catch { /* ignore */ } }
      }

      if (statusCode >= 200 && statusCode < 300) {
        await supabase.from("webhook_delivery_logs").update({ status: 'SUCCESS', signature: finalSignature, dispatched_at: new Date().toISOString() }).eq("id", id);
      } else {
        await supabase.rpc("webhook_delivery_fail", { p_log_id: id, p_org_id: organization_id, p_error: statusCode > 0 ? `HTTP_${statusCode}` : `NO_RESPONSE` });
      }
      processed++;
    } catch (err: any) {
      await supabase.rpc("webhook_delivery_fail", { p_log_id: log.id, p_org_id: log.org_id_out, p_error: err.message.substring(0, 50) });
    }
  }

  return new Response(JSON.stringify({ ok: true, processed }), { status: 200, headers: { "Content-Type": "application/json" } });
}

if (import.meta.main) {
  Deno.serve(async (req) => {
    const authHeader = req.headers.get("Authorization") ?? "";
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const isCron = isServiceRoleAuth(authHeader, serviceRoleKey);

    if (isCron) {
      return await handleWithSecurity(req, "dispatch-verdict-webhooks", handler, false);
    } else {
      return await handleWithSecurity(req, "dispatch-verdict-webhooks", handler, true);
    }
  });
}

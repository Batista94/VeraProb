/**
 * log-security-incident — Edge Function for forensic logging of security
 * incidents reported by the Flutter SuperAdminGuard.
 *
 * POST /log-security-incident
 * Body: { event_type: string, metadata: object, jwt_claims_snapshot: object }
 * Auth: JWT (any authenticated user — does NOT require super_admin or AAL2)
 *
 * **Security Contract:**
 * - Accepts reports from ANY authenticated user (the reporter is typically
 *   the unauthorized user whose access was blocked by the guard).
 * - Rate-limited to 5 requests/minute per IP to prevent abuse.
 * - jwt_claims_snapshot is sanitized before persistence (no tokens leak).
 * - Returns HTTP 200 even on DB insert failure (silent success — INV-26:
 *   do not reveal logging infrastructure state to potential attackers).
 *
 * INV-26 (Error Parity), INV-9 (Evidence Sealing)
 */

import {
  handleWithSecurity,
  type SecurityContext,
} from "../shared/handle_with_security.ts";
import { sanitizeJwtClaims } from "../shared/jwt_claims_sanitizer.ts";

// ── Rate Limiting (in-memory, per-instance) ──────────────────────────────────

export const rateLimitMap = new Map<
  string,
  { count: number; resetAt: number }
>();
export const RATE_LIMIT = 5;
export const WINDOW_MS = 60_000;

/**
 * Checks and enforces rate limiting for a given IP.
 *
 * @returns true if the request is within limits, false if rate-limited.
 */
export function checkRateLimit(ip: string): boolean {
  const now = Date.now();
  const entry = rateLimitMap.get(ip);

  if (!entry || now >= entry.resetAt) {
    // New window — reset counter
    rateLimitMap.set(ip, { count: 1, resetAt: now + WINDOW_MS });
    return true;
  }

  if (entry.count >= RATE_LIMIT) {
    return false;
  }

  entry.count++;
  return true;
}

// ── Edge Function Handler ────────────────────────────────────────────────────

Deno.serve(async (req) => {
  return await handleWithSecurity(
    req,
    "log_security_incident",
    async (ctx: SecurityContext, supabase, _req: Request) => {
      // ── 1. Enforce rate limiting (5 req/min per IP) ──────────────────
      if (!checkRateLimit(ctx.requestIp)) {
        return new Response(
          JSON.stringify({ error: "Too Many Requests" }),
          {
            status: 429,
            headers: { "Content-Type": "application/json" },
          },
        );
      }

      // ── 2. Parse and validate request body ───────────────────────────
      let body: {
        event_type?: string;
        metadata?: Record<string, unknown>;
        jwt_claims_snapshot?: Record<string, unknown>;
      };

      try {
        body = await req.clone().json();
      } catch {
        return new Response(
          JSON.stringify({ ok: true }),
          { status: 200, headers: { "Content-Type": "application/json" } },
        );
      }

      const eventType = body.event_type ?? "UNKNOWN_SECURITY_EVENT";
      const metadata = body.metadata ?? {};
      const rawClaims = body.jwt_claims_snapshot ?? {};

      // ── 3. Sanitize jwt_claims_snapshot ──────────────────────────────
      const sanitizedClaims = sanitizeJwtClaims(rawClaims);

      // ── 4. Insert into system_audit_log ──────────────────────────────
      try {
        await supabase.from("system_audit_log").insert({
          event_type: eventType,
          severity: "critical",
          source: "flutter_guard",
          actor_type: "UNAUTHORIZED",
          payload: {
            ...metadata,
            jwt_claims: sanitizedClaims,
            correlation_id: ctx.correlationId,
            ip: ctx.requestIp,
            user_agent: req.headers.get("user-agent")?.trim() || "unknown",
            timestamp_utc: new Date().toISOString(),
          },
        });
      } catch {
        // Silent failure — do not reveal logging infrastructure state
        // to potential attackers (INV-26).
        console.error(
          `[log-security-incident] Failed to insert audit log for correlation_id=${ctx.correlationId}`,
        );
      }

      // ── 5. Always return 200 (silent success) ───────────────────────
      return new Response(
        JSON.stringify({ ok: true }),
        { status: 200, headers: { "Content-Type": "application/json" } },
      );
    },
    true,  // requireAuth — any authenticated user can report
    false, // requireSuperAdmin — NOT required
    false, // requireAAL2 — NOT required
  );
});

/**
 * verify-ledger-hmac — HMAC On-Read Verification Edge Function.
 *
 * **Purpose:** Recomputes the HMAC-SHA256 signature of a canonical payload
 * and compares it against the stored signature. Used by the Dart
 * `IntegrityVerificationService` for Fail-Fast integrity checks on financial
 * data reads.
 *
 * **Key Rotation Support (INV-31-R):**
 * - Accepts versioned signatures: `v1|a1b2c3...`, `v2|deadbeef...`
 * - Uses the key version declared in the signature to verify
 * - Legacy signatures (no prefix) are treated as v1
 *
 * **Security:**
 * - Requires valid JWT (INV-1) — only authenticated users can verify
 * - HMAC secret keys NEVER leave this Edge Function
 * - Does NOT return the recomputed signature to the client (prevents oracle attacks)
 * - Only returns `{ valid: true/false, reason?: string }`
 *
 * **Usage:**
 * ```ts
 * POST /functions/v1/verify-ledger-hmac
 * Authorization: Bearer <JWT>
 * Content-Type: application/json
 *
 * {
 *   "canonical_payload": "{\"amount_cents\":50000,\"organization_id\":\"org-123\"}",
 *   "stored_signature": "v2|a1b2c3d4..."
 * }
 *
 * Response:
 * { "valid": true }
 * // OR
 * { "valid": false, "reason": "signature_mismatch" }
 * ```
 */

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { verifyPayload } from "../shared/hmac_signer.ts";
import { handleWithSecurity, type SecurityContext } from "../shared/handle_with_security.ts";

serve(async (req) => {
  return await handleWithSecurity(req, "verify-ledger-hmac", async (ctx, supabase) => {
    // Parse request body
    let body: { canonical_payload: string; stored_signature: string };
    try {
      body = await req.json();
    } catch {
      return new Response(
        JSON.stringify({ error: "Invalid JSON body" }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      );
    }

    const { canonical_payload, stored_signature } = body;

    // Validate inputs
    if (!canonical_payload || typeof canonical_payload !== "string") {
      return new Response(
        JSON.stringify({ error: "Missing or invalid 'canonical_payload'" }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      );
    }

    if (!stored_signature || typeof stored_signature !== "string") {
      return new Response(
        JSON.stringify({ error: "Missing or invalid 'stored_signature'" }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      );
    }

    // Parse the canonical payload (it's a JSON string that was already sorted)
    let payload: unknown;
    try {
      payload = JSON.parse(canonical_payload);
    } catch {
      return new Response(
        JSON.stringify({ error: "canonical_payload is not valid JSON" }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      );
    }

    // Verify HMAC — handles versioned signatures (v1|..., v2|..., etc.)
    const isValid = await verifyPayload(payload, stored_signature);

    if (isValid) {
      return new Response(
        JSON.stringify({ valid: true }),
        { status: 200, headers: { "Content-Type": "application/json" } },
      );
    }

    // ❌ Verification failed — log to audit trail but don't leak details to client
    // (INV-26: Error Parity — don't reveal whether the key was wrong or the data was tampered)
    if (typeof Sentry !== "undefined") {
      try {
        Sentry.withScope?.(
          (scope: {
            setTag: (key: string, value: string) => void;
            setContext: (key: string, value: Record<string, unknown>) => void;
          }) => {
            scope.setTag("security_event", "HMAC_VERIFICATION_FAILED");
            scope.setTag("severity", "CRITICAL");
            scope.setTag("correlation_id", ctx.correlationId);
            scope.setTag("record_id", req.headers.get("X-Record-Id") ?? "unknown");
            scope.setTag("record_type", req.headers.get("X-Record-Type") ?? "unknown");
            scope.setContext("security_context", {
              userId: ctx.userId,
              orgId: ctx.orgId,
              signatureVersion: stored_signature.split("|")[0] ?? "legacy",
            } as Record<string, unknown>);
          },
        );
      } catch {
        // Sentry not available — skip
      }
    }

    // Return minimal response — no details about WHY verification failed
    // (prevents attackers from distinguishing between wrong key vs tampered data)
    return new Response(
      JSON.stringify({ valid: false, reason: "signature_mismatch" }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  }, true); // requireAuth = true
});

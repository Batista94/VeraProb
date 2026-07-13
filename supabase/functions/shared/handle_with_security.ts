/**
 * handleWithSecurity — Universal Security Wrapper for Deno Edge Functions.
 *
 * INV-1 (Identity Sovereignty), INV-26 (Error Parity), INV-9 (Evidence Sealing)
 *
 * **Purpose:** Eliminates boilerplate duplication by providing a single entry
 * point that handles:
 * 1. Correlation ID generation (UUID v4)
 * 2. Request IP extraction (X-Forwarded-For)
 * 3. Payload hashing (SHA-256) for forensic traceability
 * 4. JWT validation via validateJwtAuth
 * 5. Sovereignty error mapping → canonical 404 (INV-26)
 * 6. X-Correlation-Id response header injection
 * 7. SecurityContext passed to the business handler
 *
 * **Security Contract:**
 * - ALL infrastructure errors are caught and mapped to 404 via
 *   sovereigntyErrorResponse() — NO Postgres error codes leak to the client.
 * - Every request is traceable: Sentry alerts contain the full SecurityContext,
 *   enabling SOC to correlate an alert to a raw_telemetry_payloads row in <30s.
 *
 * **Usage:**
 * ```ts
 * import { handleWithSecurity, type SecurityContext } from "../shared/handle_with_security.ts";
 *
 * Deno.serve(async (req) => {
 *   return await handleWithSecurity(req, "create_contract", async (ctx, supabase) => {
 *     // ctx.correlationId, ctx.requestIp, ctx.payloadHash are available
 *     // supabase is the service_role client
 *     return await handleBusinessLogic(ctx, req, supabase);
 *   });
 * });
 * ```
 */

// deno-lint-ignore no-import-prefix
import { createClient } from "jsr:@supabase/supabase-js@2";
import { sovereigntyErrorResponse } from "./sovereignty_error_mapper.ts";
import { validateJwtAuth, type JwtAuthResult } from "./jwt_auth_validator.ts";
import { sanitizeJwtClaims } from "./jwt_claims_sanitizer.ts";

// deno-lint-ignore no-explicit-any
declare const Sentry: any;

// ── Types ─────────────────────────────────────────────────────────────────────

/**
 * Forensic Security Context — carries traceability metadata for the full
 * request lifecycle. Injected into every handler and logged to Sentry.
 *
 * SOC Parity: Enables correlation of a Sentry Alert → raw_telemetry_payloads
 * row in under 30 seconds.
 */
export interface SecurityContext {
  /** UUID v4 — unique identifier for this request (forensic correlation) */
  correlationId: string;

  /** Edge Function name (e.g., "create_contract", "ingest-sascar") */
  edgeFunction: string;

  /** Storage key for the raw ingestion payload (if applicable) */
  rawPayloadId?: string;

  /** ID of the normalized canonical fact (if applicable) */
  canonicalFactId?: string;

  /** Client IP from X-Forwarded-For (or "unknown" if unavailable) */
  requestIp: string;

  /** SHA-256 hex digest of the request body */
  payloadHash?: string;

  /** User ID from validated JWT */
  userId?: string;

  /** Organization ID from JWT app_metadata */
  orgId?: string;

  /** Tenant role from JWT app_metadata.role (TENANT_ADMIN / AUDITOR / …) */
  role?: string;

  /** Session ID from JWT */
  sessionId?: string;
}

/**
 * Business handler signature — receives SecurityContext and Supabase client.
 */
export type SecurityHandler = (
  ctx: SecurityContext,
  supabase: ReturnType<typeof createClient>,
  req: Request,
) => Promise<Response>;

// ── Environment Helpers ──────────────────────────────────────────────────────

/**
 * Strict validation of development environment.
 *
 * Accepts ONLY "dev" or "development" as valid values for the ENVIRONMENT
 * variable. Rejects variations like "dev-like", "DEV", "Dev", "development "
 * (with trailing space), etc.
 *
 * Case-sensitive, no trim — prevents bypass via creative environment values.
 *
 * @returns true if ENVIRONMENT is exactly "dev" or "development"
 */
export function isDevEnvironment(): boolean {
  const env = Deno.env.get("ENVIRONMENT");
  return env === "dev" || env === "development";
}

// ── Crypto Helpers ───────────────────────────────────────────────────────────

/**
 * Generates a UUID v4 for correlation tracking.
 */
function generateCorrelationId(): string {
  return crypto.randomUUID();
}

/**
 * Computes SHA-256 hex digest of a string payload.
 *
 * INV-9: Evidence Sealing — every raw payload is cryptographically
 * hashed at ingestion for forensic traceability.
 */
async function sha256Hex(payload: string): Promise<string> {
  const encoder = new TextEncoder();
  const data = encoder.encode(payload);
  const hashBuffer = await crypto.subtle.digest("SHA-256", data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map((b) => b.toString(16).padStart(2, "0")).join("");
}

// ── Main Wrapper ─────────────────────────────────────────────────────────────

/**
 * Wraps an Edge Function handler with full security infrastructure.
 *
 * **Pipeline:**
 * 1. Generate correlationId (UUID v4)
 * 2. Extract request IP from headers
 * 3. Clone and hash the request body (SHA-256)
 * 4. Validate JWT via validateJwtAuth (INV-1)
 * 5. Build SecurityContext
 * 6. Call the business handler
 * 7. Inject X-Correlation-Id header on response
 * 8. Catch ALL errors → sovereigntyErrorResponse() (INV-26)
 *
 * @param req — The incoming HTTP request
 * @param edgeFunction — Name of this Edge Function (for forensic logging)
 * @param handler — Business logic handler receiving SecurityContext + Supabase
 * @param requireAuth — If true (default), validates JWT. Set false for
 *   webhook/ingestion endpoints that use API keys instead.
 */
export async function handleWithSecurity(
  req: Request,
  edgeFunction: string,
  handler: SecurityHandler,
  requireAuth: boolean = true,
  requireSuperAdmin: boolean = false,
  requireAAL2: boolean = false,
): Promise<Response> {
  // Step 1: Generate correlation ID
  const correlationId = generateCorrelationId();

  // Step 2: Extract client IP
  const requestIp =
    req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ??
    req.headers.get("x-real-ip") ??
    "unknown";

  // Step 3: Clone and hash the request body (SHA-256)
  let payloadHash: string | undefined;
  let rawBody: string | undefined;
  try {
    const clonedReq = req.clone();
    rawBody = await clonedReq.text();
    if (rawBody) {
      payloadHash = await sha256Hex(rawBody);
    }
  } catch {
    // Body may not be clonable — skip hashing, continue
  }

  // Step 4: Build base SecurityContext
  const ctx: SecurityContext = {
    correlationId,
    edgeFunction,
    requestIp,
    payloadHash,
  };

  // Step 5: Validate JWT (if required)
  if (requireAuth) {
    let authResult: JwtAuthResult;
    try {
      authResult = await validateJwtAuth(req);
    } catch {
      // INV-26: Any auth failure → canonical 404
      return sovereigntyErrorResponse();
    }

    if (!authResult.ok) {
      return authResult.response;
    }

    // Enrich context with validated identity
    ctx.userId = authResult.userId;
    ctx.orgId = authResult.orgId;
    ctx.sessionId = authResult.sessionId;
    const appMeta = authResult.jwtPayload.app_metadata as
      | Record<string, unknown>
      | undefined;
    if (typeof appMeta?.role === "string") {
      ctx.role = appMeta.role;
    }

    // Step 5.1: SuperAdmin Enforcement (INV-6)
    if (requireSuperAdmin) {
      const appMetadata = authResult.jwtPayload.app_metadata as { super_admin?: boolean | string } | undefined;
      const isSuperAdmin = appMetadata?.super_admin === true || 
                          appMetadata?.super_admin === "true";
      
      if (!isSuperAdmin) {
        // INV-26: Return canonical 404 to prevent inference of SuperAdmin status
        console.error(`[handleWithSecurity] SuperAdmin violation by user ${ctx.userId}`);
        return sovereigntyErrorResponse();
      }
    }

    // Step 5.2: AAL2 Enforcement (FIX-02, INV-6)
    // Activates when requireAAL2 === true OR requireSuperAdmin === true (backward compatible)
    if (requireAAL2 || requireSuperAdmin) {
      const aal = authResult.jwtPayload.aal as string | undefined;
      const isDev = isDevEnvironment();

      if (isDev) {
        // In dev, log warning and skip AAL2 enforcement
        console.warn(`[handleWithSecurity] AAL2 bypassed in dev for user ${ctx.userId} on ${edgeFunction}`);
      } else if (aal !== "aal2") {
        // Production: AAL2 is mandatory — log forensic event and reject
        console.error(`[handleWithSecurity] AAL2 violation by user ${ctx.userId} on ${edgeFunction}`);

        // Forensic logging to system_audit_log
        try {
          const auditSupabase = createClient(
            Deno.env.get("SUPABASE_URL")!,
            Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
          );
          await auditSupabase.from("system_audit_log").insert({
            event_type: "SECURITY_VIOLATION_AAL2_BYPASS",
            severity: "critical",
            source: "edge_function",
            payload: {
              correlation_id: correlationId,
              ip: requestIp,
              user_agent: req.headers.get("user-agent") ?? "unknown",
              jwt_claims: sanitizeJwtClaims(authResult.jwtPayload),
            },
            actor_type: "UNAUTHORIZED",
          });
        } catch {
          // Audit log failure must not block the security response
        }

        return sovereigntyErrorResponse();
      }
    }
  }

  // Step 6: Initialize Supabase service_role client
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // Step 7: Final Execution (INV-27)
  // Run the actual edge function handler with the enriched security context
  try {
    // deno-lint-ignore no-explicit-any
    const response = await handler(ctx, supabase as any, req);

    // Step 8: Inject correlation ID into response headers
    const headers = new Headers(response.headers);
    headers.set("X-Correlation-Id", correlationId);
    if (payloadHash) {
      headers.set("X-Payload-Hash", payloadHash);
    }

    return new Response(response.body, {
      status: response.status,
      headers,
    });
  } catch (_error) {
    // INV-26: ALL infrastructure errors → canonical 404
    // NO Postgres error codes (22P02, PGRST116, etc.) reach the client

    // Forensic logging to Sentry (if available)
    if (typeof Sentry !== "undefined") {
      try {
        Sentry.withScope?.(
          (scope: {
            setTag: (key: string, value: string) => void;
            setContext: (key: string, value: Record<string, unknown>) => void;
          }) => {
            scope.setTag("security_event", "INFRASTRUCTURE_ERROR");
            scope.setTag("severity", "HIGH");
            scope.setTag("correlation_id", correlationId);
            scope.setTag("edge_function", edgeFunction);
            scope.setContext("security_context", {
              correlationId,
              edgeFunction,
              requestIp,
              payloadHash,
              userId: ctx.userId,
              orgId: ctx.orgId,
            } as Record<string, unknown>);
          },
        );
      } catch {
        // Sentry not available — skip
      }
    }

    return sovereigntyErrorResponse();
  }
}

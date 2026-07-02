/**
 * JWT Auth Validator for Deno Edge Functions (INV-1, INV-26, INV-27).
 *
 * Decodes and validates the Supabase JWT from the `Authorization` header,
 * extracting the `organization_id` claim for tenant isolation checks.
 *
 * **Security Contract:**
 * - Stateless: no session cache, no DB calls — pure JWT decode + claim check.
 * - On ANY failure (missing token, expired, malformed, org mismatch): returns
 *   an indistinguishable HTTP 404 to prevent Oracle Attacks (INV-26).
 * - Internal forensic data (org IDs, session ID) is logged to Sentry
 *   via the `sendSecurityLog` helper — never exposed to the client.
 *
 * **Usage:**
 * ```ts
 * const auth = await validateJwtAuth(req, "org-expected-optional");
 * if (!auth.ok) return auth.response; // 404 — stop processing
 *
 * // auth.userId, auth.orgId, auth.jwtPayload are available
 * await handleBusinessLogic(auth.userId, auth.orgId, req);
 * ```
 */

import { sovereigntyErrorResponse } from "./sovereignty_error_mapper.ts";

// deno-lint-ignore no-explicit-any
declare const Sentry: any;

// ── Types ────────────────────────────────────────────────────────────────────

export interface JwtAuthSuccess {
  ok: true;
  userId: string;
  orgId: string;
  sessionId: string;
  jwtPayload: Record<string, unknown>;
}

export interface JwtAuthFailure {
  ok: false;
  response: Response;
}

export type JwtAuthResult = JwtAuthSuccess | JwtAuthFailure;

// ── JWT Decode Helpers ───────────────────────────────────────────────────────

/**
 * Decodes a JWT payload (base64url) without verifying the signature.
 *
 * **Warning:** This does NOT validate the token signature. It only extracts
 * the claims. Use Supabase's `auth.getUser()` for full validation when
 * the user identity must be cryptographically trusted.
 */
function decodeJwtPayload(
  token: string,
): Record<string, unknown> | null {
  try {
    const parts = token.split(".");
    if (parts.length !== 3) return null;

    // base64url → base64 → UTF-8
    const payloadB64 = parts[1]
      .replace(/-/g, "+")
      .replace(/_/g, "/");
    const jsonStr = decodeURIComponent(
      atob(payloadB64)
        .split("")
        .map((c) => `%${`00${c.charCodeAt(0).toString(16)}`.slice(-2)}`)
        .join(""),
    );
    return JSON.parse(jsonStr) as Record<string, unknown>;
  } catch {
    return null;
  }
}

/**
 * Extracts the Bearer token from the Authorization header.
 */
function extractBearerToken(req: Request): string | null {
  const authHeader = req.headers.get("Authorization") ?? "";
  const match = authHeader.match(/^Bearer\s+(.+)$/i);
  return match ? match[1].trim() : null;
}

// ── Main Validator ───────────────────────────────────────────────────────────

/**
 * Validates the JWT from the request and extracts the organization_id claim.
 *
 * **Validation Steps:**
 * 1. Extract Bearer token from Authorization header
 * 2. Decode JWT payload (base64url)
 * 3. Check `exp` claim for expiry
 * 4. Extract `sub` (user ID) and `app_metadata.org_id` claims
 * 5. (Optional) Verify org_id matches the expected tenant
 *
 * On ANY failure, returns a 404 response (INV-26).
 *
 * @param req — The incoming HTTP request
 * @param expectedOrgId — Optional: if provided, validates the JWT's org_id
 *   matches this value. Mismatch returns 404 (not 403) to prevent inference.
 */
// deno-lint-ignore require-await
export async function validateJwtAuth(
  req: Request,
  expectedOrgId?: string,
): Promise<JwtAuthResult> {
  // Step 1: Extract token
  const token = extractBearerToken(req);
  if (!token) {
    return _failure("Missing Authorization header", 401);
  }

  // Step 2: Decode
  const payload = decodeJwtPayload(token);
  if (!payload) {
    return _failure("Not Found");
  }

  // Step 3: Check expiry
  const exp = payload.exp as number | undefined;
  if (exp && Date.now() >= exp * 1000) {
    return _failure("Not Found");
  }

  // Step 4: Extract claims
  const userId = payload.sub as string | undefined;
  const appMetadata = payload.app_metadata as Record<string, unknown> | undefined;
  const orgId = appMetadata?.org_id as string | undefined;

  if (!userId || !orgId) {
    return _failure("Not Found");
  }

  // Step 5: Optional org_id match (INV-1: Identity Sovereignty)
  if (expectedOrgId && orgId !== expectedOrgId) {
    // INV-26: Return 404, not 403 — prevent org enumeration
    return _failure("Not Found", undefined, {
      forensicEvent: "IDENTITY_SPOOFING",
      forensicPayloadOrgId: expectedOrgId,
      forensicJwtOrgId: orgId,
      forensicUserId: userId,
    });
  }

  // Success
  return {
    ok: true,
    userId,
    orgId,
    sessionId: payload.session_id as string ?? "unknown",
    jwtPayload: payload,
  };
}

// ── Internal ─────────────────────────────────────────────────────────────────

/**
 * Returns a 404 failure response.
 *
 * INV-26: All failures return identical `{"error":"Not Found"}`.
 * Forensic context is passed for internal logging (Sentry).
 */
function _failure(
  _reason: string,
  _status?: number,
  forensicContext?: Record<string, string | undefined>,
): JwtAuthFailure {
  // Log forensic context to Sentry (if Sentry is initialized)
  if (forensicContext && typeof Sentry !== "undefined") {
    try {
      Sentry.withScope?.((scope: { setTag: (arg0: string, arg1: string) => void; setContext: (arg0: string, arg1: Record<string, string | undefined>) => void }) => {
        scope.setTag("security_event", "JWT_AUTH_FAILURE");
        scope.setTag("severity", "HIGH");
        if (forensicContext.forensicPayloadOrgId) {
          scope.setTag("payload_org_id", forensicContext.forensicPayloadOrgId);
        }
        if (forensicContext.forensicJwtOrgId) {
          scope.setTag("jwt_org_id", forensicContext.forensicJwtOrgId);
        }
        scope.setContext("forensic_data", forensicContext);
      });
    } catch {
      // Sentry not initialized — silently skip
    }
  }

  return {
    ok: false,
    response: sovereigntyErrorResponse(),
  };
}

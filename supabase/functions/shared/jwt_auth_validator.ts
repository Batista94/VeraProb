/**
 * JWT Auth Validator for Deno Edge Functions (INV-1, INV-22, INV-26).
 *
 * Cryptographically verifies the Supabase JWT via `auth.getClaims`, then
 * validates application claims. Never trusts unsigned payload decode.
 *
 * **Security Contract:**
 * - Claims come ONLY from a successful verifier (`getClaims` in production).
 * - Deadline lives in validateJwtAuth (every verifier receives AbortSignal).
 * - Principals are mutually exclusive: SuperAdmin must have org_id null/absent;
 *   tenant users must have a non-empty org_id string. Hybrid → 404.
 * - Orgless SuperAdmin is allowed ONLY when allowOrglessSuperAdmin=true
 *   (handleWithSecurity sets this iff requireSuperAdmin).
 * - On ANY failure: indistinguishable HTTP 404 (INV-26). Never log the token.
 * - Issuer: SUPABASE_JWT_ISSUER ?? `${SUPABASE_URL}/auth/v1`.
 *
 * Residual risks (backlog — see forensic_records/plans/20260721000000_jwt_p0_residual_risks.md):
 * getClaims may not see logout/ban until exp; reveal-webhook-signing-secret still lacks AAL2.
 */

// deno-lint-ignore no-import-prefix
import { createClient } from "jsr:@supabase/supabase-js@2";
import { sovereigntyErrorResponse } from "./sovereignty_error_mapper.ts";
import { withDeadline } from "./with_timeout.ts";

// deno-lint-ignore no-explicit-any
declare const Sentry: any;

export const JWT_VERIFIER_TIMEOUT_MS = 3000;

// ── Types ────────────────────────────────────────────────────────────────────

export interface JwtAuthSuccess {
  ok: true;
  userId: string;
  orgId: string | undefined;
  sessionId: string;
  jwtPayload: Record<string, unknown>;
}

export interface JwtAuthFailure {
  ok: false;
  response: Response;
}

export type JwtAuthResult = JwtAuthSuccess | JwtAuthFailure;

/**
 * Injectable claims verifier. Production default uses `auth.getClaims`.
 * Always receives AbortSignal from validateJwtAuth's single deadline.
 */
export type JwtClaimsVerifier = (
  token: string,
  signal: AbortSignal,
) => Promise<{ claims: Record<string, unknown> } | { error: true }>;

export interface ValidateJwtAuthOptions {
  expectedOrgId?: string;
  /** Default false. true only when handleWithSecurity has requireSuperAdmin. */
  allowOrglessSuperAdmin?: boolean;
  verifier?: JwtClaimsVerifier;
  /** Test-only: override fetch used by defaultJwtClaimsVerifier. */
  fetchImpl?: typeof fetch;
}

// ── Default verifier (production) ────────────────────────────────────────────

/**
 * Verifies JWT via anon client + getClaims. Propagates signal only —
 * deadline/abort is owned by validateJwtAuth.
 */
export async function defaultJwtClaimsVerifier(
  token: string,
  signal: AbortSignal,
  fetchImpl: typeof fetch = fetch,
): Promise<{ claims: Record<string, unknown> } | { error: true }> {
  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!url || !anonKey) return { error: true };

  const client = createClient(url, anonKey, {
    global: {
      fetch: (input, init) =>
        fetchImpl(input, {
          ...init,
          signal,
        }),
    },
  });
  try {
    const { data, error } = await client.auth.getClaims(token);
    if (error || data == null || data.claims == null) return { error: true };
    return { claims: data.claims as Record<string, unknown> };
  } catch {
    return { error: true };
  }
}

// ── Helpers ──────────────────────────────────────────────────────────────────

function extractBearerToken(req: Request): string | null {
  const authHeader = req.headers.get("Authorization") ?? "";
  const match = authHeader.match(/^Bearer\s+(.+)$/i);
  return match ? match[1].trim() : null;
}

function expectedIssuer(): string | null {
  const explicit = Deno.env.get("SUPABASE_JWT_ISSUER");
  if (explicit) return explicit.replace(/\/$/, "");
  const url = Deno.env.get("SUPABASE_URL");
  if (!url) return null;
  return `${url.replace(/\/$/, "")}/auth/v1`;
}

function isAuthenticatedAudience(aud: unknown): boolean {
  if (aud === "authenticated") return true;
  if (Array.isArray(aud)) {
    return aud.includes("authenticated");
  }
  return false;
}

// ── Main Validator ───────────────────────────────────────────────────────────

/**
 * Validates the JWT from the request and extracts tenant / SuperAdmin identity.
 */
export async function validateJwtAuth(
  req: Request,
  options: ValidateJwtAuthOptions = {},
): Promise<JwtAuthResult> {
  const token = extractBearerToken(req);
  if (!token) {
    return _failure("Missing Authorization header");
  }

  const verifier: JwtClaimsVerifier = options.verifier ??
    ((t, signal) =>
      defaultJwtClaimsVerifier(t, signal, options.fetchImpl ?? fetch));

  let verified: { claims: Record<string, unknown> } | { error: true };
  try {
    verified = await withDeadline(
      (signal) => verifier(token, signal),
      JWT_VERIFIER_TIMEOUT_MS,
    );
  } catch {
    return _failure("Verifier deadline/error");
  }
  if ("error" in verified) {
    return _failure("Verification failed");
  }

  const claims = verified.claims;
  const issExpected = expectedIssuer();
  if (!issExpected || claims.iss !== issExpected) {
    return _failure("Invalid issuer");
  }

  if (!isAuthenticatedAudience(claims.aud)) {
    return _failure("Invalid audience");
  }

  if (claims.role !== "authenticated") {
    return _failure("Invalid role");
  }

  const exp = claims.exp;
  if (typeof exp !== "number" || Date.now() >= exp * 1000) {
    return _failure("Expired or missing exp");
  }

  const userId = claims.sub;
  if (typeof userId !== "string" || userId.length === 0) {
    return _failure("Invalid sub");
  }

  const appMetadata = claims.app_metadata;
  if (
    typeof appMetadata !== "object" ||
    appMetadata === null ||
    Array.isArray(appMetadata)
  ) {
    return _failure("Invalid app_metadata");
  }

  const meta = appMetadata as Record<string, unknown>;
  const isSuperAdmin = meta.super_admin === true;
  const rawOrg = meta.org_id;

  let orgId: string | undefined;
  if (isSuperAdmin) {
    if (rawOrg !== null && rawOrg !== undefined) {
      return _failure("Hybrid principal");
    }
    if (options.allowOrglessSuperAdmin !== true) {
      return _failure("SA on tenant route");
    }
    orgId = undefined;
  } else {
    if (typeof rawOrg !== "string" || rawOrg.length === 0) {
      return _failure("Invalid org_id");
    }
    orgId = rawOrg;
  }

  if (options.expectedOrgId !== undefined) {
    if (orgId === undefined || orgId !== options.expectedOrgId) {
      return _failure("Not Found", {
        forensicEvent: "IDENTITY_SPOOFING",
        forensicPayloadOrgId: options.expectedOrgId,
        forensicJwtOrgId: typeof orgId === "string" ? orgId : undefined,
        forensicUserId: userId,
      });
    }
  }

  const sessionRaw = claims.session_id;
  const sessionId = typeof sessionRaw === "string" && sessionRaw.length > 0
    ? sessionRaw
    : "unknown";

  return {
    ok: true,
    userId,
    orgId,
    sessionId,
    jwtPayload: claims,
  };
}

// ── Internal ─────────────────────────────────────────────────────────────────

function _failure(
  _reason: string,
  forensicContext?: Record<string, string | undefined>,
): JwtAuthFailure {
  if (forensicContext && typeof Sentry !== "undefined") {
    try {
      Sentry.withScope?.(
        (scope: {
          setTag: (arg0: string, arg1: string) => void;
          setContext: (
            arg0: string,
            arg1: Record<string, string | undefined>,
          ) => void;
        }) => {
          scope.setTag("security_event", "JWT_AUTH_FAILURE");
          scope.setTag("severity", "HIGH");
          if (forensicContext.forensicPayloadOrgId) {
            scope.setTag(
              "payload_org_id",
              forensicContext.forensicPayloadOrgId,
            );
          }
          if (forensicContext.forensicJwtOrgId) {
            scope.setTag("jwt_org_id", forensicContext.forensicJwtOrgId);
          }
          scope.setContext("forensic_data", forensicContext);
        },
      );
    } catch {
      // Sentry not initialized — silently skip
    }
  }

  return {
    ok: false,
    response: sovereigntyErrorResponse(),
  };
}

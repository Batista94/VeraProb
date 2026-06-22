/**
 * Infrastructure Error Guard for Deno Edge Functions.
 *
 * Separates the two failure classes a portal endpoint can hit, WITHOUT leaking
 * either to the carrier beyond the agreed surface (INV-26):
 *
 *  - BUSINESS rejection (bad token, wrong state, cap reached) → opaque 404 via
 *    sovereigntyErrorResponse(). Indistinguishable, anti-oracle. Handled by the
 *    caller — this guard does NOT touch business 42501s.
 *  - INFRASTRUCTURE failure (storage signing down, DB unreachable) → this guard
 *    classifies it internally (Sentry tag error_class:"INFRA") and rethrows a
 *    typed InfrastructureUnavailableError. The caller maps it to an opaque 503
 *    via infraErrorResponse().
 *
 * Why 503 (not 404) for infra on the carrier surface: storage signing runs only
 * AFTER the RPC has authorized the token, and the portal token is a UUIDv4
 * (122-bit) unguessable credential — an attacker cannot enumerate candidate
 * tokens to weaponize the "503 ⇒ valid token" bit. The 80ms response floor +
 * per-IP rate limit are the timing/enumeration controls. A 404 here would
 * masquerade a transient outage as a permanent business rejection, breaking SRE
 * triage and (without hash idempotency) permanently consuming the carrier's
 * submission slot. This is the Stripe/AWS/GCP separation: stable minimal codes
 * externally, full classification internally.
 *
 * Single-responsibility: this module owns error CLASSIFICATION + internal
 * observability. sovereignty_error_mapper.ts owns HTTP body construction only.
 *
 * Council: Architect ✅ · Senior ✅ · QA-Security ✅ · Lead ✅
 */

/** Typed marker for a genuine infrastructure failure (vs a business rejection). */
export class InfrastructureUnavailableError extends Error {
  readonly tag: string;
  readonly cause?: unknown;

  constructor(tag: string, cause?: unknown) {
    super(`Infrastructure unavailable: ${tag}`);
    this.name = "InfrastructureUnavailableError";
    this.tag = tag;
    this.cause = cause;
  }
}

export const INFRA_STATUS = 503;
export const INFRA_BODY = JSON.stringify({ error: "Service temporarily unavailable" });

/**
 * Opaque 503 for the carrier surface. Carries NO resource/path/bucket detail —
 * the real cause is logged to Sentry inside infraErrorGuard.
 */
export function infraErrorResponse(): Response {
  return new Response(INFRA_BODY, {
    status: INFRA_STATUS,
    headers: { "Content-Type": "application/json" },
  });
}

interface InfraLogFields {
  message?: string;
  code?: string;
  details?: string;
}

function extractFields(error: unknown): InfraLogFields {
  if (error && typeof error === "object") {
    const e = error as { message?: unknown; code?: unknown; details?: unknown };
    return {
      message: typeof e.message === "string" ? e.message : undefined,
      code: typeof e.code === "string" ? e.code : undefined,
      details: typeof e.details === "string" ? e.details : undefined,
    };
  }
  return { message: String(error) };
}

/**
 * Logs an INFRASTRUCTURE failure to Sentry (error_class:"INFRA", guarded by
 * `typeof Sentry !== "undefined"` like the rest of the shared layer). Never
 * throws. Use for the `{data, error}` return shape of supabase-js calls (which
 * do NOT throw): classify the returned error yourself, then call this for the
 * infra branch and map to infraErrorResponse().
 */
export function logInfraError(
  tag: string,
  correlationId: string,
  error: unknown,
): void {
  const fields = extractFields(error);
  if (typeof Sentry !== "undefined") {
    try {
      Sentry.withScope?.(
        (scope: {
          setTag: (key: string, value: string) => void;
          setContext: (key: string, value: Record<string, unknown>) => void;
        }) => {
          scope.setTag("error_class", "INFRA");
          scope.setTag("severity", "HIGH");
          scope.setTag("correlation_id", correlationId);
          scope.setTag("infra_tag", tag);
          scope.setContext("infra_error", {
            tag,
            correlationId,
            message: fields.message,
            code: fields.code,
            details: fields.details,
          } as Record<string, unknown>);
        },
      );
    } catch {
      // Sentry not available — skip.
    }
  }
  console.error(
    `[infra] ${tag} (correlation=${correlationId}) message=${fields.message} code=${fields.code} details=${fields.details}`,
  );
}

/**
 * Runs `fn`; on throw, logs the cause via logInfraError and rethrows a typed
 * InfrastructureUnavailableError. For code paths that THROW on infra failure
 * (e.g. an unexpected exception around transport). For the supabase-js
 * `{data, error}` return shape, classify the returned error and use
 * logInfraError directly instead.
 */
export async function infraErrorGuard<T>(
  fn: () => Promise<T>,
  tag: string,
  correlationId: string,
): Promise<T> {
  try {
    return await fn();
  } catch (error) {
    logInfraError(tag, correlationId, error);
    throw new InfrastructureUnavailableError(tag, error);
  }
}

/**
 * Logs a BUSINESS-rule rejection (the RPC's opaque 42501) to Sentry with the
 * machine-parseable DETAIL token — for SRE triage — while the caller still
 * returns the byte-identical 404 (INV-26). Never throws.
 */
export function logBusinessRejection(
  tag: string,
  correlationId: string,
  error: unknown,
): void {
  const fields = extractFields(error);
  if (typeof Sentry !== "undefined") {
    try {
      Sentry.withScope?.(
        (scope: {
          setTag: (key: string, value: string) => void;
          setContext: (key: string, value: Record<string, unknown>) => void;
        }) => {
          scope.setTag("error_class", "BUSINESS_RULE");
          scope.setTag("correlation_id", correlationId);
          scope.setTag("infra_tag", tag);
          scope.setContext("business_rejection", {
            tag,
            correlationId,
            code: fields.code,
            // DETAIL token (e.g. PORTAL_SUBMIT_REJECTED:SUBMISSION_CAP_EXCEEDED).
            details: fields.details,
          } as Record<string, unknown>);
        },
      );
    } catch {
      // Sentry not available — skip.
    }
  }
  console.error(
    `[business] ${tag} (correlation=${correlationId}) code=${fields.code} details=${fields.details}`,
  );
}

/**
 * Shared JWT test helpers for injectable claims verifiers (P0 crypto JWT).
 * Production never imports this — tests only.
 */

import type { JwtClaimsVerifier } from "../shared/jwt_auth_validator.ts";

/** Verifier that always rejects (simulates forged signature / getClaims failure). */
export const rejectAll: JwtClaimsVerifier = (_token, _signal) =>
  Promise.resolve({ error: true as const });

/** Verifier that throws (fail-closed path). */
export const throwingVerifier: JwtClaimsVerifier = (_token, _signal) =>
  Promise.reject(new Error("verifier timeout"));

/** Verifier that never resolves (deadline must expire in validateJwtAuth). */
export const hangingVerifier: JwtClaimsVerifier = (_token, _signal) =>
  new Promise(() => {});

/**
 * Accepting verifier: returns crypto-"verified" claims for unit/PBT tests.
 * Merges `partial` over canonical Supabase user claims (iss/aud/role/exp/sub/org).
 * When `app_metadata.super_admin === true`, default org_id is null (exclusive SA).
 * Otherwise default org_id is "org-test" unless partial overrides.
 */
export function claimsOf(
  partial: Record<string, unknown> = {},
): JwtClaimsVerifier {
  return (_token, _signal) => {
    const url = (Deno.env.get("SUPABASE_URL") ?? "https://fake.supabase.co")
      .replace(/\/$/, "");
    const partialMeta =
      typeof partial.app_metadata === "object" &&
        partial.app_metadata !== null &&
        !Array.isArray(partial.app_metadata)
        ? partial.app_metadata as Record<string, unknown>
        : {};
    const isSa = partialMeta.super_admin === true;
    const claims: Record<string, unknown> = {
      iss: `${url}/auth/v1`,
      aud: "authenticated",
      role: "authenticated",
      exp: Math.floor(Date.now() / 1000) + 3600,
      sub: "user-test",
      session_id: "session-test",
      ...partial,
      app_metadata: {
        org_id: isSa ? null : "org-test",
        ...partialMeta,
      },
    };
    return Promise.resolve({ claims });
  };
}

/** Minimal three-segment forged JWT (signature never trusted in production). */
export function createFakeJwt(payload: Record<string, unknown>): string {
  const header = { alg: "HS256", typ: "JWT" };
  const encode = (obj: Record<string, unknown>) => {
    const json = JSON.stringify(obj);
    const b64 = btoa(json);
    return b64.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  };
  return `${encode(header)}.${encode(payload)}.fake-signature`;
}

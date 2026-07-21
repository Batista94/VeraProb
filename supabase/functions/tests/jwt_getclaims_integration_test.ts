/**
 * Live getClaims integration (host only — never run inside Docker pr-scan).
 *
 * Requires local Supabase + bootstrap_dev users.
 * Gate: REQUIRE_JWT_INTEGRATION=1 → login/Auth failure is BLOCK.
 *
 * Run: make test-jwt-integration
 *
 * Matrix: intact tenant/SA, payload-only tamper, signature-only tamper,
 * wholly forged JWT, garbage/non-JWT — all via real defaultJwtClaimsVerifier.
 */

import { assertEquals, assert } from "@std/assert";
// deno-lint-ignore no-import-prefix
import { createClient } from "jsr:@supabase/supabase-js@2";
import { validateJwtAuth } from "../shared/jwt_auth_validator.ts";
import { createFakeJwt } from "./jwt_test_helpers.ts";

const required = Deno.env.get("REQUIRE_JWT_INTEGRATION") === "1";

const liveIgnore = !required &&
  !(Deno.env.get("SUPABASE_URL") && Deno.env.get("SUPABASE_ANON_KEY"));

function envOr(key: string, fallback: string): string {
  return Deno.env.get(key) ?? fallback;
}

async function signIn(email: string, password: string): Promise<string> {
  const url = Deno.env.get("SUPABASE_URL");
  const anon = Deno.env.get("SUPABASE_ANON_KEY");
  if (!url || !anon) {
    throw new Error("SUPABASE_URL / SUPABASE_ANON_KEY required");
  }
  const client = createClient(url, anon);
  const { data, error } = await client.auth.signInWithPassword({
    email,
    password,
  });
  if (error || !data.session?.access_token) {
    throw new Error(
      `signIn failed for ${email}: ${error?.message ?? "no token"}`,
    );
  }
  return data.session.access_token;
}

function authRequest(token: string): Request {
  return new Request("https://example.com/jwt-integration", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
  });
}

function b64urlJson(obj: Record<string, unknown>): string {
  const json = JSON.stringify(obj);
  return btoa(json).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function parseJwtPayload(token: string): Record<string, unknown> {
  const parts = token.split(".");
  assertEquals(parts.length, 3, "expected three-segment JWT");
  const padded = parts[1].replace(/-/g, "+").replace(/_/g, "/");
  const pad = padded.length % 4 === 0 ? "" : "=".repeat(4 - (padded.length % 4));
  return JSON.parse(atob(padded + pad)) as Record<string, unknown>;
}

/** Keep header + signature; rewrite only the payload segment. */
function withTamperedPayload(
  token: string,
  mutate: (claims: Record<string, unknown>) => void,
): string {
  const [header, , sig] = token.split(".");
  const claims = parseJwtPayload(token);
  mutate(claims);
  return `${header}.${b64urlJson(claims)}.${sig}`;
}

/** Keep header + payload; rewrite only the signature segment. */
function withTamperedSignature(token: string): string {
  const [header, payload, sig] = token.split(".");
  const flipped = sig.length > 0
    ? (sig[0] === "A" ? "B" : "A") + sig.slice(1)
    : "x";
  return `${header}.${payload}.${flipped}`;
}

async function assertRejected(token: string, label: string): Promise<void> {
  const result = await validateJwtAuth(authRequest(token));
  assert(!result.ok, `${label} must be rejected`);
  assertEquals(result.response.status, 404, `${label} → 404`);
}

Deno.test({
  name: "getClaims: real tenant JWT accepted",
  ignore: liveIgnore,
  sanitizeOps: false,
  sanitizeResources: false,
  async fn() {
    const token = await signIn(
      envOr("JWT_TEST_TENANT_EMAIL", "admin-a@veraprob.dev"),
      envOr("JWT_TEST_TENANT_PASSWORD", "123456"),
    );
    const ok = await validateJwtAuth(authRequest(token));
    assert(ok.ok, "real tenant token must verify");
    if (ok.ok) {
      assert(typeof ok.orgId === "string" && ok.orgId.length > 0);
      assertEquals(ok.jwtPayload.role, "authenticated");
    }
  },
});

Deno.test({
  name: "getClaims: tenant — payload-only tamper → 404",
  ignore: liveIgnore,
  sanitizeOps: false,
  sanitizeResources: false,
  async fn() {
    const token = await signIn(
      envOr("JWT_TEST_TENANT_EMAIL", "admin-a@veraprob.dev"),
      envOr("JWT_TEST_TENANT_PASSWORD", "123456"),
    );
    const tampered = withTamperedPayload(token, (claims) => {
      const meta = (claims.app_metadata ?? {}) as Record<string, unknown>;
      meta.org_id = "00000000-0000-0000-0000-00000000dead";
      claims.app_metadata = meta;
    });
    await assertRejected(tampered, "tenant payload tamper");
  },
});

Deno.test({
  name: "getClaims: tenant — signature-only tamper → 404",
  ignore: liveIgnore,
  sanitizeOps: false,
  sanitizeResources: false,
  async fn() {
    const token = await signIn(
      envOr("JWT_TEST_TENANT_EMAIL", "admin-a@veraprob.dev"),
      envOr("JWT_TEST_TENANT_PASSWORD", "123456"),
    );
    await assertRejected(withTamperedSignature(token), "tenant sig tamper");
  },
});

Deno.test({
  name: "getClaims: wholly forged JWT + garbage/non-JWT → 404",
  ignore: liveIgnore,
  sanitizeOps: false,
  sanitizeResources: false,
  async fn() {
    const iss =
      `${(Deno.env.get("SUPABASE_URL") ?? "").replace(/\/$/, "")}/auth/v1`;
    const forged = createFakeJwt({
      iss,
      aud: "authenticated",
      role: "authenticated",
      exp: Math.floor(Date.now() / 1000) + 3600,
      sub: "00000000-0000-0000-0000-000000000099",
      app_metadata: { org_id: "00000000-0000-0000-0000-000000000001" },
    });
    await assertRejected(forged, "wholly forged JWT");
    await assertRejected("not-a-jwt", "garbage token");
    await assertRejected("a.b", "two-segment garbage");
  },
});

Deno.test({
  name: "getClaims: real SuperAdmin JWT (org null) on SA vs tenant routes",
  ignore: liveIgnore,
  sanitizeOps: false,
  sanitizeResources: false,
  async fn() {
    const token = await signIn(
      envOr("JWT_TEST_SUPERADMIN_EMAIL", "master@veraprob.dev"),
      envOr("JWT_TEST_SUPERADMIN_PASSWORD", "veraprob123!"),
    );

    const tenantRoute = await validateJwtAuth(authRequest(token));
    assert(!tenantRoute.ok, "orgless SA must fail tenant route");
    assertEquals(tenantRoute.response.status, 404);

    const saRoute = await validateJwtAuth(authRequest(token), {
      allowOrglessSuperAdmin: true,
    });
    assert(saRoute.ok, "orgless SA must pass allowOrglessSuperAdmin");
    if (saRoute.ok) {
      assertEquals(saRoute.orgId, undefined);
      const meta = saRoute.jwtPayload.app_metadata as Record<string, unknown>;
      assertEquals(meta.super_admin, true);
    }
  },
});

Deno.test({
  name: "getClaims: SuperAdmin — payload-only + signature-only tamper → 404",
  ignore: liveIgnore,
  sanitizeOps: false,
  sanitizeResources: false,
  async fn() {
    const token = await signIn(
      envOr("JWT_TEST_SUPERADMIN_EMAIL", "master@veraprob.dev"),
      envOr("JWT_TEST_SUPERADMIN_PASSWORD", "veraprob123!"),
    );

    const payloadTampered = withTamperedPayload(token, (claims) => {
      const meta = (claims.app_metadata ?? {}) as Record<string, unknown>;
      meta.super_admin = false;
      meta.org_id = "00000000-0000-0000-0000-000000000001";
      claims.app_metadata = meta;
    });
    const payloadResult = await validateJwtAuth(authRequest(payloadTampered), {
      allowOrglessSuperAdmin: true,
    });
    assert(!payloadResult.ok, "SA payload tamper must be rejected");
    assertEquals(payloadResult.response.status, 404);

    const sigResult = await validateJwtAuth(
      authRequest(withTamperedSignature(token)),
      { allowOrglessSuperAdmin: true },
    );
    assert(!sigResult.ok, "SA signature tamper must be rejected");
    assertEquals(sigResult.response.status, 404);
  },
});

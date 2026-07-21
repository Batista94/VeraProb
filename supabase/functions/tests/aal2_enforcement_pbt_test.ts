/**
 * Property-Based Tests for AAL2 Enforcement in handleWithSecurity
 *
 * Feature: superadmin-zero-trust-security, Property 6: Enforcement de AAL2
 *
 * **Validates: Requirements 3.1, 3.2**
 *
 * Tests that when requireAAL2=true (or requireSuperAdmin=true), only JWTs
 * with aal="aal2" are allowed through in production. In dev environment,
 * AAL2 enforcement is bypassed with a console.warn.
 *
 * Run with: deno test --no-check --allow-env --allow-net supabase/functions/tests/aal2_enforcement_pbt_test.ts
 */

import { assertEquals } from "jsr:@std/assert@1";
import fc from "fast-check";
import { handleWithSecurity, type SecurityContext } from "../shared/handle_with_security.ts";
import { claimsOf, createFakeJwt } from "./jwt_test_helpers.ts";

// ── Test Helpers ─────────────────────────────────────────────────────────────

/**
 * Creates a minimal JWT token with the given payload claims.
 * Base64url-encoded JWT (header.payload.signature) — signature
 * is not verified by our validator, only the payload is decoded.
 */
const createTestJwt = createFakeJwt;

/**
 * Creates a Request with the given JWT as Bearer token.
 */
function createAuthRequest(jwt: string): Request {
  return new Request("https://example.com/test", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${jwt}`,
      "Content-Type": "application/json",
      "User-Agent": "PBT-Test-Agent/1.0",
    },
    body: JSON.stringify({ test: true }),
  });
}

/**
 * A simple handler that returns 200 — used to verify the request
 * made it past security checks.
 */
const successHandler = async (
  _ctx: SecurityContext,
  _supabase: unknown,
  _req: Request,
): Promise<Response> => {
  return new Response(JSON.stringify({ ok: true }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
};

/**
 * Sets ENVIRONMENT and restores it after the callback.
 */
async function withEnv(
  value: string | undefined,
  fn: () => Promise<void>,
): Promise<void> {
  const original = Deno.env.get("ENVIRONMENT");
  if (value === undefined) {
    Deno.env.delete("ENVIRONMENT");
  } else {
    Deno.env.set("ENVIRONMENT", value);
  }
  // Ensure Supabase env vars are set for client creation
  const origUrl = Deno.env.get("SUPABASE_URL");
  const origKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!origUrl) Deno.env.set("SUPABASE_URL", "https://fake.supabase.co");
  if (!origKey) Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "fake-key");
  try {
    await fn();
  } finally {
    if (original === undefined) {
      Deno.env.delete("ENVIRONMENT");
    } else {
      Deno.env.set("ENVIRONMENT", original);
    }
    if (!origUrl) Deno.env.delete("SUPABASE_URL");
    if (!origKey) Deno.env.delete("SUPABASE_SERVICE_ROLE_KEY");
  }
}

// ── Generators ───────────────────────────────────────────────────────────────

/**
 * Generates AAL values that are NOT "aal2".
 * Includes null, undefined, "aal1", random strings, empty string, etc.
 */
const nonAal2ValueArb = fc.oneof(
  fc.constant("aal1"),
  fc.constant(null),
  fc.constant(undefined),
  fc.constant(""),
  fc.constant("aal3"),
  fc.constant("AAL2"),
  fc.constant("Aal2"),
  fc.constant("aal2 "),
  fc.constant(" aal2"),
  fc.string().filter((s) => s !== "aal2"),
);

/**
 * Tenant JWT payload for requireAAL2-only routes (exclusive principals).
 */
function tenantPayload(aal: unknown): Record<string, unknown> {
  return {
    sub: "user-" + crypto.randomUUID().slice(0, 8),
    aal,
    role: "authenticated",
    exp: Math.floor(Date.now() / 1000) + 3600,
    app_metadata: {
      org_id: crypto.randomUUID(),
    },
  };
}

/**
 * SuperAdmin JWT payload (org_id null) for requireSuperAdmin routes.
 */
function superAdminPayload(aal: unknown): Record<string, unknown> {
  return {
    sub: "user-" + crypto.randomUUID().slice(0, 8),
    aal,
    role: "authenticated",
    exp: Math.floor(Date.now() / 1000) + 3600,
    app_metadata: {
      super_admin: true,
      org_id: null,
    },
  };
}

// ── Property Tests ───────────────────────────────────────────────────────────

Deno.test({
  name: "Property 6: aal='aal2' passes when requireAAL2=true in production",
  sanitizeOps: false,
  sanitizeResources: false,
  async fn() {
    await withEnv("production", async () => {
      await fc.assert(
        fc.asyncProperty(fc.constant("aal2"), async (aal) => {
          const payload = tenantPayload(aal);
          const jwt = createTestJwt(payload);
          const req = createAuthRequest(jwt);

          const response = await handleWithSecurity(
            req,
            "test_function",
            successHandler,
            true,   // requireAuth
            false,  // requireSuperAdmin
            true,   // requireAAL2
            claimsOf(payload),
          );

          assertEquals(
            response.status,
            200,
            `Expected aal='aal2' to pass AAL2 enforcement, got ${response.status}`,
          );
        }),
        { numRuns: 100 },
      );
    });
  },
});

Deno.test({
  name: "Property 6: Non-aal2 values are rejected when requireAAL2=true in production",
  sanitizeOps: false,
  sanitizeResources: false,
  async fn() {
    await withEnv("production", async () => {
      await fc.assert(
        fc.asyncProperty(nonAal2ValueArb, async (aal) => {
          const payload = tenantPayload(aal);
          const jwt = createTestJwt(payload);
          const req = createAuthRequest(jwt);

          const response = await handleWithSecurity(
            req,
            "test_function",
            successHandler,
            true,   // requireAuth
            false,  // requireSuperAdmin
            true,   // requireAAL2
            claimsOf(payload),
          );

          assertEquals(
            response.status,
            404,
            `Expected aal='${aal}' to be rejected (404), got ${response.status}`,
          );
        }),
        { numRuns: 100 },
      );
    });
  },
});

Deno.test({
  name: "Property 6: requireSuperAdmin=true also enforces AAL2 (backward compatible)",
  sanitizeOps: false,
  sanitizeResources: false,
  async fn() {
    await withEnv("production", async () => {
      await fc.assert(
        fc.asyncProperty(nonAal2ValueArb, async (aal) => {
          const payload = superAdminPayload(aal);
          const jwt = createTestJwt(payload);
          const req = createAuthRequest(jwt);

          const response = await handleWithSecurity(
            req,
            "test_function",
            successHandler,
            true,  // requireAuth
            true,  // requireSuperAdmin — should also enforce AAL2
            false, // requireAAL2 — even when false, superAdmin triggers AAL2
            claimsOf(payload),
          );

          assertEquals(
            response.status,
            404,
            `Expected requireSuperAdmin=true to enforce AAL2 for aal='${aal}', got ${response.status}`,
          );
        }),
        { numRuns: 100 },
      );
    });
  },
});

Deno.test({
  name: "Property 6: AAL2 enforcement is bypassed in dev environment",
  sanitizeOps: false,
  sanitizeResources: false,
  async fn() {
    await withEnv("dev", async () => {
      await fc.assert(
        fc.asyncProperty(nonAal2ValueArb, async (aal) => {
          const payload = tenantPayload(aal);
          const jwt = createTestJwt(payload);
          const req = createAuthRequest(jwt);

          const response = await handleWithSecurity(
            req,
            "test_function",
            successHandler,
            true,   // requireAuth
            false,  // requireSuperAdmin
            true,   // requireAAL2
            claimsOf(payload),
          );

          assertEquals(
            response.status,
            200,
            `Expected AAL2 to be bypassed in dev for aal='${aal}', got ${response.status}`,
          );
        }),
        { numRuns: 100 },
      );
    });
  },
});

Deno.test({
  name: "Property 6: AAL2 enforcement is bypassed in 'development' environment",
  sanitizeOps: false,
  sanitizeResources: false,
  async fn() {
    await withEnv("development", async () => {
      await fc.assert(
        fc.asyncProperty(nonAal2ValueArb, async (aal) => {
          const payload = tenantPayload(aal);
          const jwt = createTestJwt(payload);
          const req = createAuthRequest(jwt);

          const response = await handleWithSecurity(
            req,
            "test_function",
            successHandler,
            true,   // requireAuth
            false,  // requireSuperAdmin
            true,   // requireAAL2
            claimsOf(payload),
          );

          assertEquals(
            response.status,
            200,
            `Expected AAL2 to be bypassed in 'development' for aal='${aal}', got ${response.status}`,
          );
        }),
        { numRuns: 100 },
      );
    });
  },
});

Deno.test({
  name: "Property 6: requireAAL2=false without requireSuperAdmin=false skips AAL2 check",
  sanitizeOps: false,
  sanitizeResources: false,
  async fn() {
    await withEnv("production", async () => {
      await fc.assert(
        fc.asyncProperty(nonAal2ValueArb, async (aal) => {
          const payload = tenantPayload(aal);
          const jwt = createTestJwt(payload);
          const req = createAuthRequest(jwt);

          const response = await handleWithSecurity(
            req,
            "test_function",
            successHandler,
            true,   // requireAuth
            false,  // requireSuperAdmin
            false,  // requireAAL2
            claimsOf(payload),
          );

          assertEquals(
            response.status,
            200,
            `Expected no AAL2 enforcement when both flags are false, got ${response.status}`,
          );
        }),
        { numRuns: 100 },
      );
    });
  },
});

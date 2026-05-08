/**
 * Property-Based Tests for Header Integrity on 404 Responses
 *
 * Feature: superadmin-zero-trust-security, Property 10: Integridade de headers na resposta 404
 *
 * **Validates: Requirements 6.4**
 *
 * Tests that all 404 error responses from handleWithSecurity:
 * 1. Include the X-Correlation-Id header (UUID v4 format) when applicable
 * 2. Do NOT include any revealing headers (X-Auth-Error, X-Reason,
 *    X-SuperAdmin-Required, X-AAL-Required, etc.)
 *
 * Run with: deno test --no-check --allow-env --allow-net supabase/functions/tests/headers_integrity_404_pbt_test.ts
 */

import { assertEquals, assert } from "jsr:@std/assert@1";
import fc from "fast-check";
import { handleWithSecurity, type SecurityContext } from "../shared/handle_with_security.ts";

// ── Constants ────────────────────────────────────────────────────────────────

/**
 * Headers that MUST NOT appear in 404 responses — they would reveal
 * the nature of the security failure to an attacker.
 */
const FORBIDDEN_HEADERS = [
  "x-auth-error",
  "x-reason",
  "x-superadmin-required",
  "x-aal-required",
  "x-aal-level",
  "x-security-violation",
  "x-error-type",
  "x-error-detail",
  "x-error-code",
  "x-auth-failure",
  "x-mfa-required",
  "x-admin-required",
  "x-forbidden",
  "x-access-denied",
];

const UUID_V4_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

// ── Test Helpers ─────────────────────────────────────────────────────────────

function createTestJwt(payload: Record<string, unknown>): string {
  const header = { alg: "HS256", typ: "JWT" };
  const encode = (obj: Record<string, unknown>) => {
    const json = JSON.stringify(obj);
    const b64 = btoa(json);
    return b64.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  };
  return `${encode(header)}.${encode(payload as Record<string, unknown>)}.fake-signature`;
}

function createAuthRequest(jwt?: string, userAgent?: string): Request {
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
  };
  if (jwt) {
    headers["Authorization"] = `Bearer ${jwt}`;
  }
  if (userAgent) {
    headers["User-Agent"] = userAgent;
  }
  return new Request("https://example.com/test", {
    method: "POST",
    headers,
    body: JSON.stringify({ test: true }),
  });
}

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

const throwingHandler = async (
  _ctx: SecurityContext,
  _supabase: unknown,
  _req: Request,
): Promise<Response> => {
  throw new Error("Simulated infrastructure failure");
};

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

/**
 * Asserts that a 404 response has correct header integrity:
 * - If X-Correlation-Id is present, it must be a valid UUID v4
 * - No forbidden headers are present
 */
function assertHeaderIntegrity(response: Response, context: string): void {
  assertEquals(response.status, 404, `Expected 404 for ${context}`);

  // X-Correlation-Id: if present, must be valid UUID v4.
  // Some early-return 404s (e.g., from validateJwtAuth) bypass the
  // correlation ID injection step — that's acceptable per INV-26.
  const correlationId = response.headers.get("X-Correlation-Id");
  if (correlationId) {
    assert(
      UUID_V4_REGEX.test(correlationId),
      `X-Correlation-Id should be a valid UUID v4, got: ${correlationId} (${context})`,
    );
  }

  // No forbidden headers should be present
  for (const header of FORBIDDEN_HEADERS) {
    assertEquals(
      response.headers.get(header),
      null,
      `Forbidden header '${header}' should NOT be present in 404 response (${context})`,
    );
  }
}

// ── Generators ───────────────────────────────────────────────────────────────

/**
 * Generates random User-Agent strings.
 */
const userAgentArb = fc.oneof(
  fc.constant("Mozilla/5.0 (Windows NT 10.0; Win64; x64)"),
  fc.constant("curl/7.68.0"),
  fc.constant("PostmanRuntime/7.29.0"),
  fc.string({ minLength: 1, maxLength: 100 }),
);

/**
 * Generates JWT payloads that will trigger various 404 scenarios.
 */
const failingJwtPayloadArb = fc.oneof(
  // No super_admin claim
  fc.record({
    sub: fc.uuid(),
    aal: fc.constantFrom("aal1", "aal2"),
    role: fc.constant("authenticated"),
    exp: fc.constant(Math.floor(Date.now() / 1000) + 3600),
    app_metadata: fc.record({
      super_admin: fc.constant(false),
      org_id: fc.uuid(),
    }),
  }),
  // super_admin=true but aal != aal2
  fc.record({
    sub: fc.uuid(),
    aal: fc.constantFrom("aal1", "", "AAL2", "aal3"),
    role: fc.constant("authenticated"),
    exp: fc.constant(Math.floor(Date.now() / 1000) + 3600),
    app_metadata: fc.record({
      super_admin: fc.constant(true),
      org_id: fc.uuid(),
    }),
  }),
);

// ── Property Tests ───────────────────────────────────────────────────────────

Deno.test({
  name: "Property 10: 404 from SuperAdmin rejection has correct header integrity",
  sanitizeOps: false,
  sanitizeResources: false,
  async fn() {
    await withEnv("production", async () => {
      await fc.assert(
        fc.asyncProperty(userAgentArb, async (userAgent) => {
          const payload = {
            sub: crypto.randomUUID(),
            aal: "aal2",
            role: "authenticated",
            exp: Math.floor(Date.now() / 1000) + 3600,
            app_metadata: {
              super_admin: false,
              org_id: crypto.randomUUID(),
            },
          };
          const jwt = createTestJwt(payload);
          const req = createAuthRequest(jwt, userAgent);

          const response = await handleWithSecurity(
            req,
            "test_function",
            successHandler,
            true,  // requireAuth
            true,  // requireSuperAdmin
            true,  // requireAAL2
          );

          assertHeaderIntegrity(response, `SuperAdmin rejection`);
        }),
        { numRuns: 100 },
      );
    });
  },
});

Deno.test({
  name: "Property 10: 404 from AAL2 rejection has correct header integrity",
  sanitizeOps: false,
  sanitizeResources: false,
  async fn() {
    await withEnv("production", async () => {
      const nonAal2Arb = fc.constantFrom("aal1", "", "AAL2", "aal3");

      await fc.assert(
        fc.asyncProperty(nonAal2Arb, userAgentArb, async (aal, userAgent) => {
          const payload = {
            sub: crypto.randomUUID(),
            aal,
            role: "authenticated",
            exp: Math.floor(Date.now() / 1000) + 3600,
            app_metadata: {
              super_admin: true,
              org_id: crypto.randomUUID(),
            },
          };
          const jwt = createTestJwt(payload);
          const req = createAuthRequest(jwt, userAgent);

          const response = await handleWithSecurity(
            req,
            "test_function",
            successHandler,
            true,   // requireAuth
            false,  // requireSuperAdmin
            true,   // requireAAL2
          );

          assertHeaderIntegrity(response, `AAL2 rejection with aal='${aal}'`);
        }),
        { numRuns: 100 },
      );
    });
  },
});

Deno.test({
  name: "Property 10: 404 from missing auth has correct header integrity",
  sanitizeOps: false,
  sanitizeResources: false,
  async fn() {
    await withEnv("production", async () => {
      await fc.assert(
        fc.asyncProperty(userAgentArb, async (userAgent) => {
          const req = createAuthRequest(undefined, userAgent);

          const response = await handleWithSecurity(
            req,
            "test_function",
            successHandler,
            true,  // requireAuth
            true,  // requireSuperAdmin
            true,  // requireAAL2
          );

          assertHeaderIntegrity(response, `Missing auth`);
        }),
        { numRuns: 100 },
      );
    });
  },
});

Deno.test({
  name: "Property 10: 404 from handler error has correct header integrity",
  sanitizeOps: false,
  sanitizeResources: false,
  async fn() {
    await withEnv("production", async () => {
      await fc.assert(
        fc.asyncProperty(userAgentArb, async (userAgent) => {
          const payload = {
            sub: crypto.randomUUID(),
            aal: "aal2",
            role: "authenticated",
            exp: Math.floor(Date.now() / 1000) + 3600,
            app_metadata: {
              super_admin: true,
              org_id: crypto.randomUUID(),
            },
          };
          const jwt = createTestJwt(payload);
          const req = createAuthRequest(jwt, userAgent);

          const response = await handleWithSecurity(
            req,
            "test_function",
            throwingHandler,
            true,  // requireAuth
            true,  // requireSuperAdmin
            true,  // requireAAL2
          );

          assertHeaderIntegrity(response, `Handler error`);
        }),
        { numRuns: 100 },
      );
    });
  },
});

Deno.test({
  name: "Property 10: 404 responses from varied auth states never leak forbidden headers",
  sanitizeOps: false,
  sanitizeResources: false,
  async fn() {
    await withEnv("production", async () => {
      await fc.assert(
        fc.asyncProperty(failingJwtPayloadArb, userAgentArb, async (payload, userAgent) => {
          const jwt = createTestJwt(payload as Record<string, unknown>);
          const req = createAuthRequest(jwt, userAgent);

          const response = await handleWithSecurity(
            req,
            "test_function",
            successHandler,
            true,  // requireAuth
            true,  // requireSuperAdmin
            true,  // requireAAL2
          );

          assertHeaderIntegrity(response, `Varied auth state`);
        }),
        { numRuns: 100 },
      );
    });
  },
});

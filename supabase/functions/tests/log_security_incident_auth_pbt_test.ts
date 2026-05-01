/**
 * Property-Based Tests for log-security-incident Authentication Permissiveness
 *
 * Feature: superadmin-zero-trust-security, Property 11: Permissividade de autenticação do log-security-incident
 *
 * **Validates: Requirements 9.2**
 *
 * Tests that the log-security-incident Edge Function accepts requests from
 * ANY authenticated user — regardless of super_admin claim or AAL level.
 * This is critical because the reporter is typically the unauthorized user
 * whose access was blocked by the Flutter guard.
 *
 * Run with: deno test --no-check --allow-env --allow-net supabase/functions/tests/log_security_incident_auth_pbt_test.ts
 */

import { assertEquals } from "jsr:@std/assert@1";
import fc from "fast-check";
import {
  handleWithSecurity,
  type SecurityContext,
} from "../shared/handle_with_security.ts";
import { sanitizeJwtClaims } from "../shared/jwt_claims_sanitizer.ts";
import {
  checkRateLimit,
  rateLimitMap,
  RATE_LIMIT,
} from "../log-security-incident/index.ts";

// ── Test Helpers ─────────────────────────────────────────────────────────────

/**
 * Creates a minimal JWT token with the given payload claims.
 */
function createTestJwt(payload: Record<string, unknown>): string {
  const header = { alg: "HS256", typ: "JWT" };
  const encode = (obj: Record<string, unknown>) => {
    const json = JSON.stringify(obj);
    const b64 = btoa(json);
    return b64.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  };
  return `${encode(header)}.${encode(payload as Record<string, unknown>)}.fake-signature`;
}

/**
 * Creates a POST Request with the given JWT and body payload.
 */
function createLogRequest(jwt: string): Request {
  return new Request("https://example.com/log-security-incident", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${jwt}`,
      "Content-Type": "application/json",
      "User-Agent": "PBT-Test-Agent/1.0",
      "X-Forwarded-For": `10.0.0.${Math.floor(Math.random() * 255)}`,
    },
    body: JSON.stringify({
      event_type: "SECURITY_VIOLATION_BYPASS_ATTEMPT",
      metadata: { route_attempted: "/super-admin/tenants" },
      jwt_claims_snapshot: { sub: "test-user", aal: "aal1" },
    }),
  });
}

/**
 * The handler that mirrors the log-security-incident business logic,
 * but without actual DB insertion (we test the auth permissiveness,
 * not the DB layer).
 */
const logIncidentHandler = async (
  ctx: SecurityContext,
  _supabase: unknown,
  req: Request,
): Promise<Response> => {
  // Rate limiting check — use unique IPs per test to avoid interference
  if (!checkRateLimit(ctx.requestIp)) {
    return new Response(
      JSON.stringify({ error: "Too Many Requests" }),
      { status: 429, headers: { "Content-Type": "application/json" } },
    );
  }

  // Parse body
  let body: Record<string, unknown>;
  try {
    body = await req.clone().json();
  } catch {
    return new Response(
      JSON.stringify({ ok: true }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  }

  // Sanitize claims
  const rawClaims =
    (body.jwt_claims_snapshot as Record<string, unknown>) ?? {};
  sanitizeJwtClaims(rawClaims);

  // Always return 200 (silent success)
  return new Response(JSON.stringify({ ok: true }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
};

/**
 * Sets environment variables and restores them after the callback.
 */
async function withEnv(fn: () => Promise<void>): Promise<void> {
  const origUrl = Deno.env.get("SUPABASE_URL");
  const origKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const origEnv = Deno.env.get("ENVIRONMENT");
  Deno.env.set("SUPABASE_URL", "https://fake.supabase.co");
  Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "fake-key");
  Deno.env.set("ENVIRONMENT", "production");
  try {
    await fn();
  } finally {
    if (origUrl) Deno.env.set("SUPABASE_URL", origUrl);
    else Deno.env.delete("SUPABASE_URL");
    if (origKey) Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", origKey);
    else Deno.env.delete("SUPABASE_SERVICE_ROLE_KEY");
    if (origEnv) Deno.env.set("ENVIRONMENT", origEnv);
    else Deno.env.delete("ENVIRONMENT");
  }
}

// ── Generators ───────────────────────────────────────────────────────────────

/**
 * Generates varied JWT payloads: with/without super_admin, different aal values,
 * different roles — all representing valid authenticated users.
 */
const authenticatedJwtPayloadArb = fc
  .record({
    sub: fc.uuid(),
    aal: fc.oneof(
      fc.constant("aal1"),
      fc.constant("aal2"),
      fc.constant(null),
      fc.constant(""),
      fc.stringOf(fc.char().filter((c) => /[a-zA-Z0-9]/.test(c)), { minLength: 1, maxLength: 10 }),
    ),
    role: fc.oneof(
      fc.constant("authenticated"),
      fc.constant("anon"),
      fc.constant("service_role"),
      fc.stringOf(fc.char().filter((c) => /[a-zA-Z0-9]/.test(c)), { minLength: 1, maxLength: 15 }),
    ),
    super_admin: fc.oneof(
      fc.constant(true),
      fc.constant(false),
      fc.constant(null),
      fc.constant(undefined),
    ),
    org_id: fc.uuid(),
  })
  .map(({ sub, aal, role, super_admin, org_id }) => {
    const payload: Record<string, unknown> = {
      sub,
      role,
      exp: Math.floor(Date.now() / 1000) + 3600,
      session_id: crypto.randomUUID(),
      app_metadata: {
        org_id,
        ...(super_admin !== null && super_admin !== undefined
          ? { super_admin }
          : {}),
      },
    };
    if (aal !== null) {
      payload.aal = aal;
    }
    return payload;
  });

// ── Property Tests ───────────────────────────────────────────────────────────

Deno.test({
  name: "Property 11: Any authenticated JWT receives HTTP 200 from log-security-incident (varied claims)",
  sanitizeOps: false,
  sanitizeResources: false,
  async fn() {
    await withEnv(async () => {
      // Clear rate limit map before test
      rateLimitMap.clear();

      let runIndex = 0;
      await fc.assert(
        fc.asyncProperty(authenticatedJwtPayloadArb, async (payload) => {
          runIndex++;
          // Use unique IP per run to avoid rate limiting interference
          const jwt = createTestJwt(payload);
          const req = new Request(
            "https://example.com/log-security-incident",
            {
              method: "POST",
              headers: {
                Authorization: `Bearer ${jwt}`,
                "Content-Type": "application/json",
                "User-Agent": "PBT-Test-Agent/1.0",
                "X-Forwarded-For": `10.${Math.floor(runIndex / 65025)}.${Math.floor((runIndex % 65025) / 255)}.${(runIndex % 255) + 1}`,
              },
              body: JSON.stringify({
                event_type: "SECURITY_VIOLATION_BYPASS_ATTEMPT",
                metadata: { route_attempted: "/super-admin/test" },
                jwt_claims_snapshot: payload,
              }),
            },
          );

          const response = await handleWithSecurity(
            req,
            "log_security_incident",
            logIncidentHandler,
            true,  // requireAuth
            false, // requireSuperAdmin
            false, // requireAAL2
          );

          assertEquals(
            response.status,
            200,
            `Expected HTTP 200 for authenticated user with claims ${JSON.stringify({
              super_admin: (payload.app_metadata as Record<string, unknown>)
                ?.super_admin,
              aal: payload.aal,
              role: payload.role,
            })}, got ${response.status}`,
          );
        }),
        { numRuns: 100 },
      );
    });
  },
});

Deno.test({
  name: "Property 11: Unauthenticated requests (no JWT) are rejected by handleWithSecurity",
  sanitizeOps: false,
  sanitizeResources: false,
  async fn() {
    await withEnv(async () => {
      const req = new Request("https://example.com/log-security-incident", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "User-Agent": "PBT-Test-Agent/1.0",
        },
        body: JSON.stringify({
          event_type: "SECURITY_VIOLATION_BYPASS_ATTEMPT",
          metadata: {},
          jwt_claims_snapshot: {},
        }),
      });

      const response = await handleWithSecurity(
        req,
        "log_security_incident",
        logIncidentHandler,
        true,  // requireAuth
        false, // requireSuperAdmin
        false, // requireAAL2
      );

      // Unauthenticated → 404 (INV-26)
      assertEquals(
        response.status,
        404,
        `Expected unauthenticated request to get 404, got ${response.status}`,
      );
    });
  },
});

Deno.test({
  name: "Property 11: super_admin=true with aal2 also receives HTTP 200 (not blocked)",
  sanitizeOps: false,
  sanitizeResources: false,
  async fn() {
    await withEnv(async () => {
      rateLimitMap.clear();

      await fc.assert(
        fc.asyncProperty(fc.uuid(), async (userId) => {
          const payload = {
            sub: userId,
            aal: "aal2",
            role: "authenticated",
            exp: Math.floor(Date.now() / 1000) + 3600,
            session_id: crypto.randomUUID(),
            app_metadata: {
              super_admin: true,
              org_id: crypto.randomUUID(),
            },
          };

          const jwt = createTestJwt(payload);
          const req = new Request(
            "https://example.com/log-security-incident",
            {
              method: "POST",
              headers: {
                Authorization: `Bearer ${jwt}`,
                "Content-Type": "application/json",
                "User-Agent": "PBT-Test-Agent/1.0",
                "X-Forwarded-For": `172.16.${Math.floor(Math.random() * 255)}.${Math.floor(Math.random() * 254) + 1}`,
              },
              body: JSON.stringify({
                event_type: "TEST_EVENT",
                metadata: {},
                jwt_claims_snapshot: payload,
              }),
            },
          );

          const response = await handleWithSecurity(
            req,
            "log_security_incident",
            logIncidentHandler,
            true,  // requireAuth
            false, // requireSuperAdmin
            false, // requireAAL2
          );

          assertEquals(
            response.status,
            200,
            `Expected super_admin+aal2 user to get 200, got ${response.status}`,
          );
        }),
        { numRuns: 100 },
      );
    });
  },
});

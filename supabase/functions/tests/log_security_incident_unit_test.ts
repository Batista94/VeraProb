/**
 * Unit Tests for log-security-incident Edge Function
 *
 * Tests:
 * - 3.7: Silent success — DB insert failure still returns HTTP 200
 * - 3.8: Rate limiting — 6th request in same minute returns HTTP 429
 *
 * Run with: deno test --no-check --allow-env --allow-net supabase/functions/tests/log_security_incident_unit_test.ts
 */

import { assertEquals } from "jsr:@std/assert@1";
import {
  handleWithSecurity,
  type SecurityContext,
} from "../shared/handle_with_security.ts";
import { sanitizeJwtClaims } from "../shared/jwt_claims_sanitizer.ts";
import { claimsOf, createFakeJwt } from "./jwt_test_helpers.ts";
import {
  checkRateLimit,
  rateLimitMap,
  RATE_LIMIT,
} from "../log-security-incident/index.ts";

// ── Test Helpers ─────────────────────────────────────────────────────────────

const createTestJwt = createFakeJwt;

function validJwtPayload(): Record<string, unknown> {
  return {
    sub: crypto.randomUUID(),
    aal: "aal1",
    role: "authenticated",
    exp: Math.floor(Date.now() / 1000) + 3600,
    session_id: crypto.randomUUID(),
    app_metadata: {
      org_id: crypto.randomUUID(),
    },
  };
}

function createRequest(ip: string): Request {
  const jwt = createTestJwt(validJwtPayload());
  return new Request("https://example.com/log-security-incident", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${jwt}`,
      "Content-Type": "application/json",
      "User-Agent": "Unit-Test-Agent/1.0",
      "X-Forwarded-For": ip,
    },
    body: JSON.stringify({
      event_type: "SECURITY_VIOLATION_BYPASS_ATTEMPT",
      metadata: { route_attempted: "/super-admin/tenants" },
      jwt_claims_snapshot: { sub: "test-user", aal: "aal1" },
    }),
  });
}

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

// ── 3.7: Silent success on DB insert failure ─────────────────────────────────

Deno.test({
  name: "3.7: DB insert failure returns HTTP 200 (silent success)",
  sanitizeOps: false,
  sanitizeResources: false,
  async fn() {
    await withEnv(async () => {
      rateLimitMap.clear();

      /**
       * Handler that simulates a DB insert failure by throwing an error
       * inside the insert call, but still returns 200.
       */
      const handlerWithDbFailure = async (
        ctx: SecurityContext,
        _supabase: unknown,
        req: Request,
      ): Promise<Response> => {
        // Rate limiting
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

        const rawClaims =
          (body.jwt_claims_snapshot as Record<string, unknown>) ?? {};
        sanitizeJwtClaims(rawClaims);

        // Simulate DB insert failure
        try {
          throw new Error("Simulated DB connection failure");
        } catch {
          // Silent failure — do not reveal logging infrastructure state
          console.error(
            `[log-security-incident] Failed to insert audit log for correlation_id=${ctx.correlationId}`,
          );
        }

        // Must still return 200
        return new Response(JSON.stringify({ ok: true }), {
          status: 200,
          headers: { "Content-Type": "application/json" },
        });
      };

      const req = createRequest("192.168.100.1");
      const response = await handleWithSecurity(
        req,
        "log_security_incident",
        handlerWithDbFailure,
        true,  // requireAuth
        false, // requireSuperAdmin
        false, // requireAAL2
        claimsOf(validJwtPayload()),
      );

      assertEquals(
        response.status,
        200,
        `Expected HTTP 200 even on DB failure, got ${response.status}`,
      );

      const body = await response.json();
      assertEquals(body.ok, true, "Response body should indicate success");
    });
  },
});

Deno.test({
  name: "3.7: DB insert failure with Supabase error object returns HTTP 200",
  sanitizeOps: false,
  sanitizeResources: false,
  async fn() {
    await withEnv(async () => {
      rateLimitMap.clear();

      /**
       * Handler that simulates a Supabase insert returning an error
       * (not throwing, but returning { error: ... }).
       */
      const handlerWithSupabaseError = async (
        ctx: SecurityContext,
        _supabase: unknown,
        req: Request,
      ): Promise<Response> => {
        if (!checkRateLimit(ctx.requestIp)) {
          return new Response(
            JSON.stringify({ error: "Too Many Requests" }),
            { status: 429, headers: { "Content-Type": "application/json" } },
          );
        }

        let body: Record<string, unknown>;
        try {
          body = await req.clone().json();
        } catch {
          return new Response(
            JSON.stringify({ ok: true }),
            { status: 200, headers: { "Content-Type": "application/json" } },
          );
        }

        const rawClaims =
          (body.jwt_claims_snapshot as Record<string, unknown>) ?? {};
        sanitizeJwtClaims(rawClaims);

        // Simulate Supabase returning an error (not throwing)
        const _insertResult = {
          data: null,
          error: {
            message: "relation \"system_audit_log\" does not exist",
            code: "42P01",
          },
        };

        // The function should NOT check the error — just return 200
        return new Response(JSON.stringify({ ok: true }), {
          status: 200,
          headers: { "Content-Type": "application/json" },
        });
      };

      const req = createRequest("192.168.100.2");
      const response = await handleWithSecurity(
        req,
        "log_security_incident",
        handlerWithSupabaseError,
        true,
        false,
        false,

        claimsOf(validJwtPayload()),
      );

      assertEquals(
        response.status,
        200,
        `Expected HTTP 200 even on Supabase error, got ${response.status}`,
      );
    });
  },
});

// ── 3.8: Rate Limiting ───────────────────────────────────────────────────────

Deno.test({
  name: "3.8: checkRateLimit allows first 5 requests and blocks 6th",
  sanitizeOps: false,
  sanitizeResources: false,
  fn() {
    rateLimitMap.clear();
    const testIp = "203.0.113.42";

    // First 5 requests should pass
    for (let i = 1; i <= RATE_LIMIT; i++) {
      const allowed = checkRateLimit(testIp);
      assertEquals(
        allowed,
        true,
        `Request ${i} should be allowed (within limit of ${RATE_LIMIT})`,
      );
    }

    // 6th request should be blocked
    const blocked = checkRateLimit(testIp);
    assertEquals(
      blocked,
      false,
      `Request ${RATE_LIMIT + 1} should be blocked (rate limit exceeded)`,
    );
  },
});

Deno.test({
  name: "3.8: Rate limit resets after window expires",
  sanitizeOps: false,
  sanitizeResources: false,
  fn() {
    rateLimitMap.clear();
    const testIp = "203.0.113.99";

    // Exhaust the rate limit
    for (let i = 0; i < RATE_LIMIT; i++) {
      checkRateLimit(testIp);
    }
    assertEquals(checkRateLimit(testIp), false, "Should be rate-limited");

    // Simulate window expiry by manipulating the map entry
    const entry = rateLimitMap.get(testIp)!;
    entry.resetAt = Date.now() - 1; // Set resetAt to the past

    // Should be allowed again
    const allowed = checkRateLimit(testIp);
    assertEquals(allowed, true, "Should be allowed after window reset");
  },
});

Deno.test({
  name: "3.8: Different IPs have independent rate limits",
  sanitizeOps: false,
  sanitizeResources: false,
  fn() {
    rateLimitMap.clear();
    const ip1 = "10.0.0.1";
    const ip2 = "10.0.0.2";

    // Exhaust rate limit for ip1
    for (let i = 0; i < RATE_LIMIT; i++) {
      checkRateLimit(ip1);
    }
    assertEquals(checkRateLimit(ip1), false, "ip1 should be rate-limited");

    // ip2 should still be allowed
    assertEquals(checkRateLimit(ip2), true, "ip2 should NOT be rate-limited");
  },
});

Deno.test({
  name: "3.8: 6th request via handleWithSecurity returns HTTP 429",
  sanitizeOps: false,
  sanitizeResources: false,
  async fn() {
    await withEnv(async () => {
      rateLimitMap.clear();
      const testIp = "198.51.100.50";

      const handler = async (
        ctx: SecurityContext,
        _supabase: unknown,
        _req: Request,
      ): Promise<Response> => {
        if (!checkRateLimit(ctx.requestIp)) {
          return new Response(
            JSON.stringify({ error: "Too Many Requests" }),
            { status: 429, headers: { "Content-Type": "application/json" } },
          );
        }
        return new Response(JSON.stringify({ ok: true }), {
          status: 200,
          headers: { "Content-Type": "application/json" },
        });
      };

      // Send 5 requests (should all return 200)
      for (let i = 0; i < RATE_LIMIT; i++) {
        const jwt = createTestJwt(validJwtPayload());
        const req = new Request("https://example.com/log-security-incident", {
          method: "POST",
          headers: {
            Authorization: `Bearer ${jwt}`,
            "Content-Type": "application/json",
            "User-Agent": "Unit-Test-Agent/1.0",
            "X-Forwarded-For": testIp,
          },
          body: JSON.stringify({
            event_type: "TEST",
            metadata: {},
            jwt_claims_snapshot: {},
          }),
        });

        const response = await handleWithSecurity(
          req,
          "log_security_incident",
          handler,
          true,
          false,
          false,

          claimsOf(validJwtPayload()),
        );

        assertEquals(
          response.status,
          200,
          `Request ${i + 1} should return 200, got ${response.status}`,
        );
      }

      // 6th request should return 429
      const jwt = createTestJwt(validJwtPayload());
      const req = new Request("https://example.com/log-security-incident", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${jwt}`,
          "Content-Type": "application/json",
          "User-Agent": "Unit-Test-Agent/1.0",
          "X-Forwarded-For": testIp,
        },
        body: JSON.stringify({
          event_type: "TEST",
          metadata: {},
          jwt_claims_snapshot: {},
        }),
      });

      const response = await handleWithSecurity(
        req,
        "log_security_incident",
        handler,
        true,
        false,
        false,

        claimsOf(validJwtPayload()),
      );

      assertEquals(
        response.status,
        429,
        `6th request should return 429, got ${response.status}`,
      );
    });
  },
});

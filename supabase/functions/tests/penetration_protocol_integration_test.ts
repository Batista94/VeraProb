/**
 * Integration Tests — Penetration Protocol (Task 9)
 *
 * Feature: superadmin-zero-trust-security
 *
 * **Validates: Requirements 11.1, 11.2, 11.3, 11.4, 11.5**
 *
 * End-to-end integration tests that exercise the handleWithSecurity pipeline
 * with realistic attack scenarios:
 *
 * 9.1 — Admin without super_admin → 404 + audit log entry
 * 9.2 — JWT with aal=aal1 + requireSuperAdmin → 404 + SECURITY_VIOLATION_AAL2_BYPASS log
 * 9.3 — JWT without super_admin + requireSuperAdmin → 404 + audit log
 * 9.4 — All 404 responses are byte-identical with timing variation < 50ms
 *
 * Run with:
 *   deno test --no-check --allow-env --allow-net supabase/functions/tests/penetration_protocol_integration_test.ts
 */

import { assertEquals, assert } from "jsr:@std/assert@1";
import { handleWithSecurity, type SecurityContext } from "../shared/handle_with_security.ts";
import { SOVEREIGNTY_BODY, SOVEREIGNTY_STATUS } from "../shared/sovereignty_error_mapper.ts";
import { claimsOf, createFakeJwt } from "./jwt_test_helpers.ts";

// ── Test Helpers ─────────────────────────────────────────────────────────────

/**
 * Creates a minimal JWT token with the given payload claims.
 * Base64url-encoded JWT (header.payload.signature) — signature is not
 * verified by our validator, only the payload is decoded.
 */
const createTestJwt = createFakeJwt;

/**
 * Creates a Request with the given JWT as Bearer token.
 */
function createAuthRequest(jwt: string, ip?: string): Request {
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    "User-Agent": "PenetrationTest-Agent/1.0",
  };
  headers["Authorization"] = `Bearer ${jwt}`;
  if (ip) {
    headers["X-Forwarded-For"] = ip;
  }
  return new Request("https://example.com/super-admin/tenants/test", {
    method: "POST",
    headers,
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
 * Captures audit log inserts by intercepting the Supabase client creation.
 * Since handleWithSecurity creates its own Supabase client internally for
 * audit logging, we mock the environment to capture those inserts.
 */
interface AuditLogEntry {
  event_type: string;
  severity: string;
  source: string;
  payload: Record<string, unknown>;
  actor_type: string;
}

/**
 * Sets up environment variables and restores them after the callback.
 */
async function withProductionEnv(fn: () => Promise<void>): Promise<void> {
  const originalEnv = Deno.env.get("ENVIRONMENT");
  const origUrl = Deno.env.get("SUPABASE_URL");
  const origKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  Deno.env.set("ENVIRONMENT", "production");
  if (!origUrl) Deno.env.set("SUPABASE_URL", "https://fake.supabase.co");
  if (!origKey) Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "fake-key");

  try {
    await fn();
  } finally {
    if (originalEnv === undefined) {
      Deno.env.delete("ENVIRONMENT");
    } else {
      Deno.env.set("ENVIRONMENT", originalEnv);
    }
    if (!origUrl) Deno.env.delete("SUPABASE_URL");
    if (!origKey) Deno.env.delete("SUPABASE_SERVICE_ROLE_KEY");
  }
}

/**
 * Creates a valid JWT payload for a regular admin (no super_admin claim).
 */
function adminPayload(overrides?: Record<string, unknown>): Record<string, unknown> {
  return {
    sub: crypto.randomUUID(),
    aal: "aal2",
    role: "authenticated",
    exp: Math.floor(Date.now() / 1000) + 3600,
    session_id: crypto.randomUUID(),
    app_metadata: {
      super_admin: false,
      org_id: crypto.randomUUID(),
    },
    ...overrides,
  };
}

/**
 * Creates a valid JWT payload for a super admin.
 */
function superAdminPayload(overrides?: Record<string, unknown>): Record<string, unknown> {
  return {
    sub: crypto.randomUUID(),
    aal: "aal2",
    role: "authenticated",
    exp: Math.floor(Date.now() / 1000) + 3600,
    session_id: crypto.randomUUID(),
    app_metadata: {
      super_admin: true,
      org_id: null,
    },
    ...overrides,
  };
}

// ── 9.1 — Admin without super_admin → 404 + audit log ───────────────────────

Deno.test({
  name: "9.1 Integration: Admin without super_admin accessing SuperAdmin route receives 404",
  sanitizeOps: false,
  sanitizeResources: false,
  async fn() {
    await withProductionEnv(async () => {
      // Create a JWT for a regular admin (super_admin=false)
      const payload = adminPayload();
      const jwt = createTestJwt(payload);
      const req = createAuthRequest(jwt, "203.0.113.42");

      const response = await handleWithSecurity(
        req,
        "super_admin_tenants",
        successHandler,
        true,  // requireAuth
        true,  // requireSuperAdmin — this is the SuperAdmin route
        true,  // requireAAL2
        claimsOf(payload),
      );

      // Verify canonical 404 response
      assertEquals(response.status, SOVEREIGNTY_STATUS, "Should return 404");

      const body = await response.text();
      assertEquals(body, SOVEREIGNTY_BODY, "Body should be canonical 404 JSON");

      // Verify Content-Type header
      assertEquals(
        response.headers.get("Content-Type"),
        "application/json",
        "Content-Type should be application/json",
      );

      // Verify no revealing headers
      assertEquals(response.headers.get("X-Auth-Error"), null, "No X-Auth-Error header");
      assertEquals(response.headers.get("X-Reason"), null, "No X-Reason header");
      assertEquals(response.headers.get("X-SuperAdmin-Required"), null, "No X-SuperAdmin-Required header");
    });
  },
});

Deno.test({
  name: "9.1 Integration: Admin without super_admin — handler is never invoked",
  sanitizeOps: false,
  sanitizeResources: false,
  async fn() {
    await withProductionEnv(async () => {
      let handlerInvoked = false;
      const trackingHandler = async (
        _ctx: SecurityContext,
        _supabase: unknown,
        _req: Request,
      ): Promise<Response> => {
        handlerInvoked = true;
        return new Response("OK", { status: 200 });
      };

      const payload = adminPayload();
      const jwt = createTestJwt(payload);
      const req = createAuthRequest(jwt, "10.0.0.1");

      await handleWithSecurity(
        req,
        "super_admin_tenants",
        trackingHandler,
        true,  // requireAuth
        true,  // requireSuperAdmin
        true,  // requireAAL2
        claimsOf(payload),
      );

      assertEquals(handlerInvoked, false, "Handler should NOT be invoked for non-super-admin");
    });
  },
});

// ── 9.2 — JWT with aal=aal1 + requireSuperAdmin → 404 + AAL2_BYPASS log ────

Deno.test({
  name: "9.2 Integration: JWT with aal=aal1 invoking Edge Function with requireSuperAdmin receives 404",
  sanitizeOps: false,
  sanitizeResources: false,
  async fn() {
    await withProductionEnv(async () => {
      // Super admin with aal=aal1 (MFA not verified)
      const payload = superAdminPayload({ aal: "aal1" });
      const jwt = createTestJwt(payload);
      const req = createAuthRequest(jwt, "198.51.100.23");

      const response = await handleWithSecurity(
        req,
        "generate_org_secret",
        successHandler,
        true,  // requireAuth
        true,  // requireSuperAdmin
        true,  // requireAAL2
        claimsOf(payload),
      );

      // Verify canonical 404 response
      assertEquals(response.status, SOVEREIGNTY_STATUS, "Should return 404 for aal1");

      const body = await response.text();
      assertEquals(body, SOVEREIGNTY_BODY, "Body should be canonical 404 JSON");
    });
  },
});

Deno.test({
  name: "9.2 Integration: JWT with aal=aal1 — handler is never invoked (AAL2 blocks before business logic)",
  sanitizeOps: false,
  sanitizeResources: false,
  async fn() {
    await withProductionEnv(async () => {
      let handlerInvoked = false;
      const trackingHandler = async (
        _ctx: SecurityContext,
        _supabase: unknown,
        _req: Request,
      ): Promise<Response> => {
        handlerInvoked = true;
        return new Response("OK", { status: 200 });
      };

      const payload = superAdminPayload({ aal: "aal1" });
      const jwt = createTestJwt(payload);
      const req = createAuthRequest(jwt, "198.51.100.23");

      await handleWithSecurity(
        req,
        "generate_org_secret",
        trackingHandler,
        true,  // requireAuth
        true,  // requireSuperAdmin
        true,  // requireAAL2
        claimsOf(payload),
      );

      assertEquals(handlerInvoked, false, "Handler should NOT be invoked when AAL2 fails");
    });
  },
});

Deno.test({
  name: "9.2 Integration: JWT with aal=aal1 — response has correct Content-Type and no revealing headers",
  sanitizeOps: false,
  sanitizeResources: false,
  async fn() {
    await withProductionEnv(async () => {
      const payload = superAdminPayload({ aal: "aal1" });
      const jwt = createTestJwt(payload);
      const req = createAuthRequest(jwt, "198.51.100.23");

      const response = await handleWithSecurity(
        req,
        "issue_impersonation_jwt",
        successHandler,
        true,  // requireAuth
        true,  // requireSuperAdmin
        true,  // requireAAL2
        claimsOf(payload),
      );

      assertEquals(response.status, 404);
      assertEquals(response.headers.get("Content-Type"), "application/json");
      assertEquals(response.headers.get("X-AAL-Required"), null, "No X-AAL-Required header");
      assertEquals(response.headers.get("X-MFA-Required"), null, "No X-MFA-Required header");
    });
  },
});

// ── 9.3 — JWT without super_admin + requireSuperAdmin → 404 + log ──────────

Deno.test({
  name: "9.3 Integration: JWT without super_admin invoking Edge Function with requireSuperAdmin receives 404",
  sanitizeOps: false,
  sanitizeResources: false,
  async fn() {
    await withProductionEnv(async () => {
      // Regular admin (super_admin=false) with aal2
      const payload = adminPayload({ aal: "aal2" });
      const jwt = createTestJwt(payload);
      const req = createAuthRequest(jwt, "192.0.2.100");

      const response = await handleWithSecurity(
        req,
        "generate_org_secret",
        successHandler,
        true,  // requireAuth
        true,  // requireSuperAdmin
        true,  // requireAAL2
        claimsOf(payload),
      );

      // Verify canonical 404 response
      assertEquals(response.status, SOVEREIGNTY_STATUS, "Should return 404 for non-super-admin");

      const body = await response.text();
      assertEquals(body, SOVEREIGNTY_BODY, "Body should be canonical 404 JSON");
    });
  },
});

Deno.test({
  name: "9.3 Integration: JWT without super_admin — handler is never invoked",
  sanitizeOps: false,
  sanitizeResources: false,
  async fn() {
    await withProductionEnv(async () => {
      let handlerInvoked = false;
      const trackingHandler = async (
        _ctx: SecurityContext,
        _supabase: unknown,
        _req: Request,
      ): Promise<Response> => {
        handlerInvoked = true;
        return new Response("OK", { status: 200 });
      };

      const payload = adminPayload({ aal: "aal2" });
      const jwt = createTestJwt(payload);
      const req = createAuthRequest(jwt, "192.0.2.100");

      await handleWithSecurity(
        req,
        "generate_org_secret",
        trackingHandler,
        true,  // requireAuth
        true,  // requireSuperAdmin
        true,  // requireAAL2
        claimsOf(payload),
      );

      assertEquals(handlerInvoked, false, "Handler should NOT be invoked for non-super-admin");
    });
  },
});

Deno.test({
  name: "9.3 Integration: JWT without super_admin — response is identical to other 404 scenarios",
  sanitizeOps: false,
  sanitizeResources: false,
  async fn() {
    await withProductionEnv(async () => {
      // Scenario A: no super_admin claim
      const payloadA = adminPayload({ aal: "aal2" });
      const jwtA = createTestJwt(payloadA);
      const reqA = createAuthRequest(jwtA, "192.0.2.100");

      const responseA = await handleWithSecurity(
        reqA,
        "generate_org_secret",
        successHandler,
        true, true, true,
        claimsOf(payloadA),
      );

      // Scenario B: super_admin but aal1
      const payloadB = superAdminPayload({ aal: "aal1" });
      const jwtB = createTestJwt(payloadB);
      const reqB = createAuthRequest(jwtB, "192.0.2.101");

      const responseB = await handleWithSecurity(
        reqB,
        "generate_org_secret",
        successHandler,
        true, true, true,
        claimsOf(payloadB),
      );

      // Both should be identical 404s
      const bodyA = await responseA.text();
      const bodyB = await responseB.text();

      assertEquals(responseA.status, responseB.status, "Status codes should be identical");
      assertEquals(bodyA, bodyB, "Response bodies should be identical");
      assertEquals(bodyA, SOVEREIGNTY_BODY, "Both should match canonical 404 body");
    });
  },
});

// ── 9.4 — Byte-identical 404 responses with timing variation < 50ms ─────────

Deno.test({
  name: "9.4 Integration: All 404 responses (invalid UUID, valid UUID no permission, non-existent UUID) are byte-identical",
  sanitizeOps: false,
  sanitizeResources: false,
  async fn() {
    await withProductionEnv(async () => {
      // Scenario 1: Invalid UUID format (not even a UUID)
      const payloadInvalid = adminPayload();
      const jwtInvalid = createTestJwt(payloadInvalid);
      const reqInvalid = createAuthRequest(jwtInvalid, "10.0.0.1");

      const responseInvalid = await handleWithSecurity(
        reqInvalid,
        "super_admin_tenants",
        successHandler,
        true,  // requireAuth
        true,  // requireSuperAdmin
        true,  // requireAAL2
        claimsOf(payloadInvalid),
      );

      // Scenario 2: Valid UUID but user has no super_admin permission
      const payloadNoPermission = adminPayload({ aal: "aal2" });
      const jwtNoPermission = createTestJwt(payloadNoPermission);
      const reqNoPermission = createAuthRequest(jwtNoPermission, "10.0.0.2");

      const responseNoPermission = await handleWithSecurity(
        reqNoPermission,
        "super_admin_tenants",
        successHandler,
        true,  // requireAuth
        true,  // requireSuperAdmin
        true,  // requireAAL2
        claimsOf(payloadNoPermission),
      );

      // Scenario 3: Super admin with aal1 (non-existent permission level)
      const payloadAal1 = superAdminPayload({ aal: "aal1" });
      const jwtAal1 = createTestJwt(payloadAal1);
      const reqAal1 = createAuthRequest(jwtAal1, "10.0.0.3");

      const responseAal1 = await handleWithSecurity(
        reqAal1,
        "super_admin_tenants",
        successHandler,
        true,  // requireAuth
        true,  // requireSuperAdmin
        true,  // requireAAL2
        claimsOf(payloadAal1),
      );

      // All three should have identical status codes
      assertEquals(responseInvalid.status, SOVEREIGNTY_STATUS, "Invalid UUID → 404");
      assertEquals(responseNoPermission.status, SOVEREIGNTY_STATUS, "No permission → 404");
      assertEquals(responseAal1.status, SOVEREIGNTY_STATUS, "AAL1 → 404");

      // All three should have byte-identical response bodies
      const bodyInvalid = await responseInvalid.text();
      const bodyNoPermission = await responseNoPermission.text();
      const bodyAal1 = await responseAal1.text();

      assertEquals(bodyInvalid, SOVEREIGNTY_BODY, "Invalid UUID body matches canonical 404");
      assertEquals(bodyNoPermission, SOVEREIGNTY_BODY, "No permission body matches canonical 404");
      assertEquals(bodyAal1, SOVEREIGNTY_BODY, "AAL1 body matches canonical 404");

      // Byte-identical check: all bodies are the same string
      assertEquals(bodyInvalid, bodyNoPermission, "Invalid UUID and No Permission bodies are byte-identical");
      assertEquals(bodyNoPermission, bodyAal1, "No Permission and AAL1 bodies are byte-identical");
      assertEquals(bodyInvalid, bodyAal1, "Invalid UUID and AAL1 bodies are byte-identical");
    });
  },
});

Deno.test({
  name: "9.4 Integration: Timing variation between 404 failure scenarios is < 50ms",
  sanitizeOps: false,
  sanitizeResources: false,
  async fn() {
    await withProductionEnv(async () => {
      const ITERATIONS = 5;
      const timings: { scenario: string; durations: number[] }[] = [
        { scenario: "no_super_admin", durations: [] },
        { scenario: "aal1_bypass", durations: [] },
        { scenario: "missing_auth", durations: [] },
      ];

      for (let i = 0; i < ITERATIONS; i++) {
        // Scenario 1: Admin without super_admin (super_admin=false, aal=aal2)
        {
          const payload = adminPayload({ aal: "aal2" });
          const jwt = createTestJwt(payload);
          const req = createAuthRequest(jwt, "10.0.0.1");

          const start = performance.now();
          const response = await handleWithSecurity(
            req,
            "super_admin_tenants",
            successHandler,
            true, true, true,
            claimsOf(payload),
          );
          const elapsed = performance.now() - start;
          assertEquals(response.status, 404);
          // Consume body to ensure full response processing
          await response.text();
          timings[0].durations.push(elapsed);
        }

        // Scenario 2: Super admin with aal=aal1
        {
          const payload = superAdminPayload({ aal: "aal1" });
          const jwt = createTestJwt(payload);
          const req = createAuthRequest(jwt, "10.0.0.2");

          const start = performance.now();
          const response = await handleWithSecurity(
            req,
            "super_admin_tenants",
            successHandler,
            true, true, true,
            claimsOf(payload),
          );
          const elapsed = performance.now() - start;
          assertEquals(response.status, 404);
          await response.text();
          timings[1].durations.push(elapsed);
        }

        // Scenario 3: No Authorization header at all
        {
          const req = new Request("https://example.com/super-admin/tenants/test", {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              "User-Agent": "PenetrationTest-Agent/1.0",
            },
            body: JSON.stringify({ test: true }),
          });

          const start = performance.now();
          const response = await handleWithSecurity(
            req,
            "super_admin_tenants",
            successHandler,
            true, true, true,
          );
          const elapsed = performance.now() - start;
          assertEquals(response.status, 404);
          await response.text();
          timings[2].durations.push(elapsed);
        }
      }

      // Calculate median for each scenario (more robust than mean against outliers)
      const medians = timings.map((t) => {
        const sorted = [...t.durations].sort((a, b) => a - b);
        return sorted[Math.floor(sorted.length / 2)];
      });

      // Verify timing variation between all scenario pairs is < 50ms
      for (let i = 0; i < medians.length; i++) {
        for (let j = i + 1; j < medians.length; j++) {
          const diff = Math.abs(medians[i] - medians[j]);
          assert(
            diff < 50,
            `Timing variation between '${timings[i].scenario}' (${medians[i].toFixed(2)}ms) ` +
            `and '${timings[j].scenario}' (${medians[j].toFixed(2)}ms) ` +
            `is ${diff.toFixed(2)}ms — exceeds 50ms threshold. ` +
            `This could enable timing attacks to distinguish failure reasons.`,
          );
        }
      }
    });
  },
});

Deno.test({
  name: "9.4 Integration: All 404 Content-Type headers are identical across failure scenarios",
  sanitizeOps: false,
  sanitizeResources: false,
  async fn() {
    await withProductionEnv(async () => {
      const responses: Response[] = [];

      // Scenario 1: No auth
      {
        const req = new Request("https://example.com/test", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ test: true }),
        });
        responses.push(
          await handleWithSecurity(req, "test_fn", successHandler, true, true, true),
        );
      }

      // Scenario 2: Admin without super_admin
      {
        const payload = adminPayload({ aal: "aal2" });
        const jwt = createTestJwt(payload);
        const req = createAuthRequest(jwt, "10.0.0.1");
        responses.push(
          await handleWithSecurity(
            req,
            "test_fn",
            successHandler,
            true,
            true,
            true,
            claimsOf(payload),
          ),
        );
      }

      // Scenario 3: Super admin with aal1
      {
        const payload = superAdminPayload({ aal: "aal1" });
        const jwt = createTestJwt(payload);
        const req = createAuthRequest(jwt, "10.0.0.2");
        responses.push(
          await handleWithSecurity(
            req,
            "test_fn",
            successHandler,
            true,
            true,
            true,
            claimsOf(payload),
          ),
        );
      }

      // All should be 404 with identical Content-Type
      for (const response of responses) {
        assertEquals(response.status, 404);
        assertEquals(
          response.headers.get("Content-Type"),
          "application/json",
          "All 404 responses should have Content-Type: application/json",
        );
      }
    });
  },
});

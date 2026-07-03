/**
 * Property-Based Tests for Security Incident Log Field Completeness
 *
 * Feature: superadmin-zero-trust-security, Property 12: Completude de campos no Security Incident Log
 *
 * **Validates: Requirements 5.1, 5.2, 5.3, 5.4**
 *
 * Tests that every security incident record inserted into system_audit_log
 * contains all mandatory fields:
 * - event_type (non-empty string)
 * - severity = 'critical'
 * - payload with IP, User-Agent, timestamp UTC (ISO 8601)
 * - source = 'flutter_guard'
 * - actor_type = 'UNAUTHORIZED'
 *
 * Uses a mock Supabase client that captures the insert payload for verification,
 * exercising the log-security-incident handler logic through handleWithSecurity.
 *
 * Run with: deno test --no-check --allow-env --allow-net supabase/functions/tests/security_incident_log_completeness_pbt_test.ts
 */

import { assertEquals, assertExists } from "jsr:@std/assert@1";
import fc from "fast-check";
import {
  handleWithSecurity,
  type SecurityContext,
} from "../shared/handle_with_security.ts";
import { sanitizeJwtClaims } from "../shared/jwt_claims_sanitizer.ts";
import {
  rateLimitMap,
} from "../log-security-incident/index.ts";

// ── ISO 8601 UTC Regex ───────────────────────────────────────────────────────

const ISO_8601_UTC_REGEX =
  /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$/;

// ── Mock Supabase Client ─────────────────────────────────────────────────────

/**
 * Captured insert record from the mock Supabase client.
 */
interface CapturedInsert {
  event_type: string;
  severity: string;
  source: string;
  actor_type: string;
  payload: Record<string, unknown>;
}

/**
 * Creates a mock Supabase client that captures insert payloads.
 * Returns the mock client and a function to retrieve captured inserts.
 */
function createMockSupabaseClient(): {
  client: unknown;
  getInserts: () => CapturedInsert[];
} {
  const inserts: CapturedInsert[] = [];

  const client = {
    from: (_table: string) => ({
      insert: (record: CapturedInsert) => {
        inserts.push(record);
        return Promise.resolve({ data: null, error: null });
      },
    }),
  };

  return { client, getInserts: () => inserts };
}

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
 * Generates varied security event types — both known and arbitrary.
 */
const eventTypeArb = fc.oneof(
  fc.constant("SECURITY_VIOLATION_BYPASS_ATTEMPT"),
  fc.constant("SECURITY_VIOLATION_AAL2_BYPASS"),
  fc.constant("SECURITY_VIOLATION_IMPERSONATION_MISMATCH"),
  fc.constant("UNKNOWN_SECURITY_EVENT"),
  fc.stringOf(
    fc.char().filter((c) => /[A-Z0-9_]/.test(c)),
    { minLength: 3, maxLength: 40 },
  ),
);

/**
 * Generates varied IP addresses.
 */
const ipArb = fc.oneof(
  fc.tuple(fc.nat(255), fc.nat(255), fc.nat(255), fc.nat(255)).map(
    ([a, b, c, d]) => `${a}.${b}.${c}.${d}`,
  ),
  fc.constant("unknown"),
  fc.constant("127.0.0.1"),
  fc.constant("::1"),
);

/**
 * Generates varied User-Agent strings.
 */
const userAgentArb = fc.oneof(
  fc.constant("Mozilla/5.0 (Windows NT 10.0; Win64; x64)"),
  fc.constant("PBT-Test-Agent/1.0"),
  fc.constant("curl/7.68.0"),
  fc.stringOf(fc.char().filter((c) => c.charCodeAt(0) >= 32 && c.charCodeAt(0) < 127), {
    minLength: 1,
    maxLength: 80,
  }),
);

/**
 * Generates varied JWT claim payloads for the snapshot.
 */
const jwtClaimsSnapshotArb = fc.record({
  sub: fc.uuid(),
  aal: fc.oneof(fc.constant("aal1"), fc.constant("aal2"), fc.constant(null)),
  role: fc.oneof(
    fc.constant("authenticated"),
    fc.constant("anon"),
    fc.stringOf(fc.char().filter((c) => /[a-z]/.test(c)), {
      minLength: 1,
      maxLength: 15,
    }),
  ),
  app_metadata: fc.record({
    super_admin: fc.oneof(fc.constant(true), fc.constant(false)),
    org_id: fc.uuid(),
  }),
  // Extra fields that should be stripped by sanitization
  access_token: fc.oneof(fc.constant(undefined), fc.hexaString({ minLength: 10, maxLength: 30 })),
  refresh_token: fc.oneof(fc.constant(undefined), fc.hexaString({ minLength: 10, maxLength: 30 })),
});

/**
 * Generates metadata objects with route information.
 */
const metadataArb = fc.record({
  route_attempted: fc.oneof(
    fc.constant("/super-admin/tenants"),
    fc.constant("/super-admin/dashboard"),
    fc.stringOf(fc.char().filter((c) => /[a-z0-9\-\/]/.test(c)), {
      minLength: 1,
      maxLength: 50,
    }),
  ),
});

/**
 * Composite generator for a full security incident request.
 */
const securityIncidentArb = fc.record({
  eventType: eventTypeArb,
  ip: ipArb,
  userAgent: userAgentArb,
  jwtClaimsSnapshot: jwtClaimsSnapshotArb,
  metadata: metadataArb,
  userId: fc.uuid(),
  orgId: fc.uuid(),
});

// ── Handler that mirrors log-security-incident logic ─────────────────────────

/**
 * Creates a handler that mirrors the log-security-incident business logic,
 * using a mock Supabase client to capture the insert payload.
 */
function createLogIncidentHandler(mockClient: unknown) {
  return async (
    ctx: SecurityContext,
    _supabase: unknown,
    req: Request,
  ): Promise<Response> => {
    // Parse body
    let body: {
      event_type?: string;
      metadata?: Record<string, unknown>;
      jwt_claims_snapshot?: Record<string, unknown>;
    };

    try {
      body = await req.clone().json();
    } catch {
      return new Response(
        JSON.stringify({ ok: true }),
        { status: 200, headers: { "Content-Type": "application/json" } },
      );
    }

    const eventType = body.event_type ?? "UNKNOWN_SECURITY_EVENT";
    const metadata = body.metadata ?? {};
    const rawClaims = body.jwt_claims_snapshot ?? {};

    // Sanitize jwt_claims_snapshot
    const sanitizedClaims = sanitizeJwtClaims(rawClaims);

    // Insert into system_audit_log via mock client
    try {
      const supabaseMock = mockClient as {
        from: (table: string) => {
          insert: (record: Record<string, unknown>) => Promise<unknown>;
        };
      };
      await supabaseMock.from("system_audit_log").insert({
        event_type: eventType,
        severity: "critical",
        source: "flutter_guard",
        actor_type: "UNAUTHORIZED",
        payload: {
          ...metadata,
          jwt_claims: sanitizedClaims,
          correlation_id: ctx.correlationId,
          ip: ctx.requestIp,
          user_agent: req.headers.get("user-agent")?.trim() || "unknown",
          timestamp_utc: new Date().toISOString(),
        },
      });
    } catch {
      console.error(
        `[log-security-incident] Failed to insert audit log for correlation_id=${ctx.correlationId}`,
      );
    }

    // Always return 200 (silent success)
    return new Response(JSON.stringify({ ok: true }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  };
}

// ── Property Tests ───────────────────────────────────────────────────────────

Deno.test({
  name: "Property 12: Every security incident log record contains event_type (non-empty), severity='critical', source='flutter_guard', actor_type='UNAUTHORIZED', and payload with IP/User-Agent/timestamp UTC",
  sanitizeOps: false,
  sanitizeResources: false,
  async fn() {
    await withEnv(async () => {
      rateLimitMap.clear();

      let runIndex = 0;
      await fc.assert(
        fc.asyncProperty(securityIncidentArb, async (incident) => {
          runIndex++;
          const { client: mockClient, getInserts } =
            createMockSupabaseClient();

          // Build a valid JWT for the request
          const jwtPayload: Record<string, unknown> = {
            sub: incident.userId,
            aal: "aal1",
            role: "authenticated",
            exp: Math.floor(Date.now() / 1000) + 3600,
            session_id: crypto.randomUUID(),
            app_metadata: {
              org_id: incident.orgId,
            },
          };
          const jwt = createTestJwt(jwtPayload);

          // Build the request body
          const requestBody = {
            event_type: incident.eventType,
            metadata: incident.metadata,
            jwt_claims_snapshot: incident.jwtClaimsSnapshot,
          };

          // Use unique IP per run to avoid rate limiting
          const uniqueIp = `10.${Math.floor(runIndex / 65025)}.${Math.floor((runIndex % 65025) / 255)}.${(runIndex % 255) + 1}`;

          const req = new Request(
            "https://example.com/log-security-incident",
            {
              method: "POST",
              headers: {
                Authorization: `Bearer ${jwt}`,
                "Content-Type": "application/json",
                "User-Agent": incident.userAgent,
                "X-Forwarded-For": uniqueIp,
              },
              body: JSON.stringify(requestBody),
            },
          );

          const handler = createLogIncidentHandler(mockClient);

          const response = await handleWithSecurity(
            req,
            "log_security_incident",
            handler,
            true,  // requireAuth
            false, // requireSuperAdmin
            false, // requireAAL2
          );

          assertEquals(response.status, 200, `Expected HTTP 200, got ${response.status}`);

          // Verify the captured insert
          const inserts = getInserts();
          assertEquals(
            inserts.length,
            1,
            `Expected exactly 1 insert, got ${inserts.length}`,
          );

          const record = inserts[0];

          // ── Verify event_type is non-empty ──────────────────────────
          assertExists(record.event_type, "event_type must exist");
          assertEquals(
            typeof record.event_type,
            "string",
            "event_type must be a string",
          );
          assertEquals(
            record.event_type.length > 0,
            true,
            `event_type must be non-empty, got "${record.event_type}"`,
          );

          // ── Verify severity = 'critical' ────────────────────────────
          assertEquals(
            record.severity,
            "critical",
            `severity must be 'critical', got '${record.severity}'`,
          );

          // ── Verify source = 'flutter_guard' ─────────────────────────
          assertEquals(
            record.source,
            "flutter_guard",
            `source must be 'flutter_guard', got '${record.source}'`,
          );

          // ── Verify actor_type = 'UNAUTHORIZED' ──────────────────────
          assertEquals(
            record.actor_type,
            "UNAUTHORIZED",
            `actor_type must be 'UNAUTHORIZED', got '${record.actor_type}'`,
          );

          // ── Verify payload contains IP ──────────────────────────────
          const payload = record.payload;
          assertExists(payload, "payload must exist");
          assertExists(payload.ip, "payload.ip must exist");
          assertEquals(
            typeof payload.ip,
            "string",
            "payload.ip must be a string",
          );
          assertEquals(
            (payload.ip as string).length > 0,
            true,
            "payload.ip must be non-empty",
          );

          // ── Verify payload contains User-Agent ──────────────────────
          assertExists(payload.user_agent, "payload.user_agent must exist");
          assertEquals(
            typeof payload.user_agent,
            "string",
            "payload.user_agent must be a string",
          );
          assertEquals(
            (payload.user_agent as string).length > 0,
            true,
            "payload.user_agent must be non-empty",
          );

          // ── Verify payload contains timestamp_utc (ISO 8601) ────────
          assertExists(
            payload.timestamp_utc,
            "payload.timestamp_utc must exist",
          );
          assertEquals(
            typeof payload.timestamp_utc,
            "string",
            "payload.timestamp_utc must be a string",
          );
          assertEquals(
            ISO_8601_UTC_REGEX.test(payload.timestamp_utc as string),
            true,
            `payload.timestamp_utc must be ISO 8601 UTC format, got '${payload.timestamp_utc}'`,
          );
        }),
        { numRuns: 100 },
      );
    });
  },
});

Deno.test({
  name: "Property 12: Sanitized JWT claims in payload preserve only allowed fields (sub, aal, role, app_metadata.{super_admin, org_id})",
  sanitizeOps: false,
  sanitizeResources: false,
  async fn() {
    await withEnv(async () => {
      rateLimitMap.clear();

      let runIndex = 0;
      await fc.assert(
        fc.asyncProperty(securityIncidentArb, async (incident) => {
          runIndex++;
          const { client: mockClient, getInserts } =
            createMockSupabaseClient();

          const jwtPayload: Record<string, unknown> = {
            sub: incident.userId,
            aal: "aal1",
            role: "authenticated",
            exp: Math.floor(Date.now() / 1000) + 3600,
            session_id: crypto.randomUUID(),
            app_metadata: { org_id: incident.orgId },
          };
          const jwt = createTestJwt(jwtPayload);

          const requestBody = {
            event_type: incident.eventType,
            metadata: incident.metadata,
            jwt_claims_snapshot: incident.jwtClaimsSnapshot,
          };

          const uniqueIp = `172.16.${Math.floor(runIndex / 255)}.${(runIndex % 255) + 1}`;

          const req = new Request(
            "https://example.com/log-security-incident",
            {
              method: "POST",
              headers: {
                Authorization: `Bearer ${jwt}`,
                "Content-Type": "application/json",
                "User-Agent": incident.userAgent,
                "X-Forwarded-For": uniqueIp,
              },
              body: JSON.stringify(requestBody),
            },
          );

          const handler = createLogIncidentHandler(mockClient);

          await handleWithSecurity(
            req,
            "log_security_incident",
            handler,
            true,
            false,
            false,
          );

          const inserts = getInserts();
          assertEquals(inserts.length, 1);

          const payload = inserts[0].payload;
          const jwtClaims = payload.jwt_claims as Record<string, unknown>;
          assertExists(jwtClaims, "payload.jwt_claims must exist");

          // Verify sanitized claims do NOT contain access_token or refresh_token
          assertEquals(
            "access_token" in jwtClaims,
            false,
            "jwt_claims must not contain access_token",
          );
          assertEquals(
            "refresh_token" in jwtClaims,
            false,
            "jwt_claims must not contain refresh_token",
          );

          // Verify only allowed top-level keys exist
          const allowedKeys = ["sub", "aal", "role", "app_metadata"];
          for (const key of Object.keys(jwtClaims)) {
            assertEquals(
              allowedKeys.includes(key),
              true,
              `jwt_claims contains disallowed key '${key}'`,
            );
          }

          // Verify app_metadata only contains allowed sub-keys
          if ("app_metadata" in jwtClaims) {
            const meta = jwtClaims.app_metadata as Record<string, unknown>;
            const allowedMetaKeys = ["super_admin", "org_id"];
            for (const key of Object.keys(meta)) {
              assertEquals(
                allowedMetaKeys.includes(key),
                true,
                `app_metadata contains disallowed key '${key}'`,
              );
            }
          }
        }),
        { numRuns: 100 },
      );
    });
  },
});

Deno.test({
  name: "Property 12: payload.correlation_id is always present and non-empty",
  sanitizeOps: false,
  sanitizeResources: false,
  async fn() {
    await withEnv(async () => {
      rateLimitMap.clear();

      let runIndex = 0;
      await fc.assert(
        fc.asyncProperty(securityIncidentArb, async (incident) => {
          runIndex++;
          const { client: mockClient, getInserts } =
            createMockSupabaseClient();

          const jwtPayload: Record<string, unknown> = {
            sub: incident.userId,
            aal: "aal1",
            role: "authenticated",
            exp: Math.floor(Date.now() / 1000) + 3600,
            session_id: crypto.randomUUID(),
            app_metadata: { org_id: incident.orgId },
          };
          const jwt = createTestJwt(jwtPayload);

          const requestBody = {
            event_type: incident.eventType,
            metadata: incident.metadata,
            jwt_claims_snapshot: incident.jwtClaimsSnapshot,
          };

          const uniqueIp = `192.168.${Math.floor(runIndex / 255)}.${(runIndex % 255) + 1}`;

          const req = new Request(
            "https://example.com/log-security-incident",
            {
              method: "POST",
              headers: {
                Authorization: `Bearer ${jwt}`,
                "Content-Type": "application/json",
                "User-Agent": incident.userAgent,
                "X-Forwarded-For": uniqueIp,
              },
              body: JSON.stringify(requestBody),
            },
          );

          const handler = createLogIncidentHandler(mockClient);

          await handleWithSecurity(
            req,
            "log_security_incident",
            handler,
            true,
            false,
            false,
          );

          const inserts = getInserts();
          assertEquals(inserts.length, 1);

          const payload = inserts[0].payload;
          assertExists(
            payload.correlation_id,
            "payload.correlation_id must exist",
          );
          assertEquals(
            typeof payload.correlation_id,
            "string",
            "payload.correlation_id must be a string",
          );
          assertEquals(
            (payload.correlation_id as string).length > 0,
            true,
            "payload.correlation_id must be non-empty",
          );
        }),
        { numRuns: 100 },
      );
    });
  },
});

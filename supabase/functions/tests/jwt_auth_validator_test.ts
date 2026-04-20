/**
 * JWT Auth Validator Tests (INV-1, INV-26)
 *
 * Run with: deno test --allow-env --allow-net supabase/functions/tests/jwt_auth_validator_test.ts
 */

import { assertEquals, assert } from "jsr:@std/assert@1";
import { validateJwtAuth } from "../shared/jwt_auth_validator.ts";

// ── Helpers ──────────────────────────────────────────────────────────────────

/**
 * Creates a fake JWT with the given payload.
 * Structure: header.payload.signature (all base64url-encoded)
 */
function createFakeJwt(payload: Record<string, unknown>): string {
  const header = btoa(JSON.stringify({ alg: "HS256", typ: "JWT" }));
  const payloadB64 = btoa(JSON.stringify(payload));
  const signature = btoa("fake-signature");
  return `${header}.${payloadB64}.${signature}`;
}

/**
 * Creates a Request with the given Authorization header and body.
 */
function createRequest(token: string | null, method = "POST"): Request {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (token) {
    headers["Authorization"] = `Bearer ${token}`;
  }
  return new Request("https://example.com", {
    method,
    headers,
  });
}

// ── Tests ────────────────────────────────────────────────────────────────────

Deno.test("validateJwtAuth returns 404 when Authorization header is missing", async () => {
  const req = createRequest(null);
  const result = await validateJwtAuth(req);

  assert(!result.ok);
  assertEquals(result.response.status, 404);
});

Deno.test("validateJwtAuth returns 404 when token is malformed", async () => {
  const req = createRequest("not-a-jwt");
  const result = await validateJwtAuth(req);

  assert(!result.ok);
  assertEquals(result.response.status, 404);
});

Deno.test("validateJwtAuth returns 404 when token is expired", async () => {
  const expiredPayload = {
    sub: "user-1",
    exp: Math.floor(Date.now() / 1000) - 3600, // 1 hour ago
    app_metadata: { org_id: "org-123" },
  };
  const token = createFakeJwt(expiredPayload);
  const req = createRequest(token);
  const result = await validateJwtAuth(req);

  assert(!result.ok);
  assertEquals(result.response.status, 404);
});

Deno.test("validateJwtAuth returns 404 when app_metadata lacks org_id", async () => {
  const payload = {
    sub: "user-no-org",
    exp: Math.floor(Date.now() / 1000) + 3600, // 1 hour from now
    app_metadata: { role: "operator" },
  };
  const token = createFakeJwt(payload);
  const req = createRequest(token);
  const result = await validateJwtAuth(req);

  assert(!result.ok);
  assertEquals(result.response.status, 404);
});

Deno.test("validateJwtAuth returns 404 when org_id mismatches expectedOrgId (INV-1)", async () => {
  const payload = {
    sub: "user-1",
    exp: Math.floor(Date.now() / 1000) + 3600,
    app_metadata: { org_id: "org-attacker" },
  };
  const token = createFakeJwt(payload);
  const req = createRequest(token);
  const result = await validateJwtAuth(req, "org-victim");

  // INV-26: 404, not 403 — prevent org enumeration
  assert(!result.ok);
  assertEquals(result.response.status, 404);
});

Deno.test("validateJwtAuth succeeds when org_id matches expectedOrgId", async () => {
  const payload = {
    sub: "user-1",
    exp: Math.floor(Date.now() / 1000) + 3600,
    app_metadata: { org_id: "org-legitimate" },
  };
  const token = createFakeJwt(payload);
  const req = createRequest(token);
  const result = await validateJwtAuth(req, "org-legitimate");

  assert(result.ok);
  if (result.ok) {
    assertEquals(result.userId, "user-1");
    assertEquals(result.orgId, "org-legitimate");
  }
});

Deno.test("validateJwtAuth succeeds without expectedOrgId check", async () => {
  const payload = {
    sub: "user-1",
    exp: Math.floor(Date.now() / 1000) + 3600,
    app_metadata: { org_id: "org-any" },
  };
  const token = createFakeJwt(payload);
  const req = createRequest(token);
  const result = await validateJwtAuth(req);

  assert(result.ok);
  if (result.ok) {
    assertEquals(result.userId, "user-1");
    assertEquals(result.orgId, "org-any");
  }
});

Deno.test("validateJwtAuth error response body is indistinguishable (INV-26)", async () => {
  const missingAuthReq = createRequest(null);
  const malformedReq = createRequest("garbage");
  const expiredReq = createRequest(createFakeJwt({
    sub: "user-1",
    exp: Math.floor(Date.now() / 1000) - 100,
    app_metadata: { org_id: "org-1" },
  }));
  const mismatchReq = createRequest(createFakeJwt({
    sub: "user-1",
    exp: Math.floor(Date.now() / 1000) + 3600,
    app_metadata: { org_id: "org-attacker" },
  }));

  const results = await Promise.all([
    validateJwtAuth(missingAuthReq),
    validateJwtAuth(malformedReq),
    validateJwtAuth(expiredReq),
    validateJwtAuth(mismatchReq, "org-victim"),
  ]);

  // All must be 404
  for (const r of results) {
    assert(!r.ok);
    assertEquals(r.response.status, 404);
  }

  // All bodies must be identical
  const bodies = await Promise.all(
    results.map((r) => r.response.text()),
  );
  const firstBody = bodies[0];
  for (const body of bodies) {
    assertEquals(body, firstBody);
  }
  assertEquals(firstBody, '{"error":"Not Found"}');
});

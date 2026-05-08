/**
 * Unit Tests for Task 7.3 — Tenant_ID Validation in Edge Functions
 *
 * Verifies that invalid UUIDs return 404 (sovereigntyErrorResponse) without
 * executing any database queries. Uses a mock Supabase client that tracks
 * whether .from() was called.
 *
 * Run with: deno test --no-check --allow-env --allow-net supabase/functions/tests/tenant_id_edge_function_unit_test.ts
 */

import { assertEquals } from "jsr:@std/assert@1";
import { isValidUuidV4, validateTenantId } from "../shared/tenant_id_validator.ts";
import { sovereigntyErrorResponse, SOVEREIGNTY_STATUS, SOVEREIGNTY_BODY } from "../shared/sovereignty_error_mapper.ts";

// ── Mock Supabase Client ─────────────────────────────────────────────────────

/**
 * Creates a mock Supabase client that tracks whether any DB query was attempted.
 * If .from() is called, it sets `queryCalled` to true — this lets us assert
 * that invalid UUIDs never trigger DB queries.
 */
function createMockSupabaseClient() {
  const tracker = { queryCalled: false, tableName: "" };

  const client = {
    from(table: string) {
      tracker.queryCalled = true;
      tracker.tableName = table;
      return {
        select(_columns: string) {
          return {
            eq(_col: string, _val: string) {
              return {
                single() {
                  return Promise.resolve({
                    data: { id: "mock-id", name: "Mock Org", status: "ACTIVE" },
                    error: null,
                  });
                },
              };
            },
          };
        },
      };
    },
  };

  return { client, tracker };
}

// ── 7.3: Invalid UUID returns 404 without DB queries ─────────────────────────

Deno.test({
  name: "7.3: validateTenantId with invalid UUID returns { valid: false } without DB query",
  sanitizeOps: false,
  sanitizeResources: false,
  async fn() {
    const invalidUuids = [
      "not-a-uuid",
      "",
      "12345",
      "zzzzzzzz-zzzz-4zzz-8zzz-zzzzzzzzzzzz",
      "550e8400-e29b-41d4-a716",           // truncated
      "550e8400-e29b-11d4-a716-446655440000", // UUID v1 (not v4)
      "INVALID-UUID-FORMAT",
      "../../etc/passwd",                    // path traversal attempt
      "<script>alert(1)</script>",           // XSS attempt
      "' OR 1=1 --",                         // SQL injection attempt
    ];

    for (const invalidId of invalidUuids) {
      const { client, tracker } = createMockSupabaseClient();

      const result = await validateTenantId(invalidId, client);

      assertEquals(
        result.valid,
        false,
        `Expected { valid: false } for invalid UUID "${invalidId}"`,
      );
      assertEquals(
        tracker.queryCalled,
        false,
        `DB query should NOT be called for invalid UUID "${invalidId}" — fail-fast violated`,
      );
    }
  },
});

Deno.test({
  name: "7.3: validateTenantId with valid UUID v4 DOES execute DB query",
  sanitizeOps: false,
  sanitizeResources: false,
  async fn() {
    const validUuid = "550e8400-e29b-41d4-a716-446655440000";
    const { client, tracker } = createMockSupabaseClient();

    const result = await validateTenantId(validUuid, client);

    assertEquals(
      result.valid,
      true,
      "Expected { valid: true } for valid UUID v4",
    );
    assertEquals(
      tracker.queryCalled,
      true,
      "DB query SHOULD be called for valid UUID v4",
    );
    assertEquals(
      tracker.tableName,
      "organizations",
      "Query should target the 'organizations' table",
    );
  },
});

Deno.test({
  name: "7.3: isValidUuidV4 rejects non-UUID strings before any DB interaction",
  sanitizeOps: false,
  sanitizeResources: false,
  fn() {
    // These should all be rejected at the format level
    assertEquals(isValidUuidV4("not-a-uuid"), false);
    assertEquals(isValidUuidV4(""), false);
    assertEquals(isValidUuidV4("550e8400-e29b-11d4-a716-446655440000"), false); // v1
    assertEquals(isValidUuidV4("550e8400-e29b-31d4-a716-446655440000"), false); // v3
    assertEquals(isValidUuidV4("550e8400-e29b-51d4-a716-446655440000"), false); // v5

    // These should pass format validation
    assertEquals(isValidUuidV4("550e8400-e29b-41d4-a716-446655440000"), true);  // v4
    assertEquals(isValidUuidV4("a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11"), true);  // v4
  },
});

Deno.test({
  name: "7.3: sovereigntyErrorResponse returns canonical 404 with correct body",
  sanitizeOps: false,
  sanitizeResources: false,
  async fn() {
    const response = sovereigntyErrorResponse();

    assertEquals(response.status, SOVEREIGNTY_STATUS, "Status should be 404");
    assertEquals(response.status, 404, "Status should be 404");

    const body = await response.text();
    assertEquals(body, SOVEREIGNTY_BODY, "Body should be canonical error JSON");
    assertEquals(body, '{"error":"Not Found"}', "Body should match exact canonical format");

    assertEquals(
      response.headers.get("Content-Type"),
      "application/json",
      "Content-Type should be application/json",
    );
  },
});

Deno.test({
  name: "7.3: validateTenantId with valid UUID but DELETED org returns { valid: false }",
  sanitizeOps: false,
  sanitizeResources: false,
  async fn() {
    const validUuid = "a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11";

    // Mock client that returns a DELETED org
    const tracker = { queryCalled: false };
    const client = {
      from(_table: string) {
        tracker.queryCalled = true;
        return {
          select(_columns: string) {
            return {
              eq(_col: string, _val: string) {
                return {
                  single() {
                    return Promise.resolve({
                      data: { id: validUuid, name: "Deleted Org", status: "DELETED" },
                      error: null,
                    });
                  },
                };
              },
            };
          },
        };
      },
    };

    const result = await validateTenantId(validUuid, client);

    assertEquals(result.valid, false, "DELETED org should return { valid: false }");
    assertEquals(tracker.queryCalled, true, "DB query should be called for valid UUID format");
  },
});

Deno.test({
  name: "7.3: validateTenantId with valid UUID but DB error returns { valid: false }",
  sanitizeOps: false,
  sanitizeResources: false,
  async fn() {
    const validUuid = "b1ffbc99-9c0b-4ef8-bb6d-6bb9bd380a22";

    // Mock client that returns a DB error (org not found)
    const client = {
      from(_table: string) {
        return {
          select(_columns: string) {
            return {
              eq(_col: string, _val: string) {
                return {
                  single() {
                    return Promise.resolve({
                      data: null,
                      error: { message: "Row not found", code: "PGRST116" },
                    });
                  },
                };
              },
            };
          },
        };
      },
    };

    const result = await validateTenantId(validUuid, client);

    assertEquals(result.valid, false, "DB error should return { valid: false }");
  },
});

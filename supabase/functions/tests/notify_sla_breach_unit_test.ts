/**
 * Unit Tests for Edge Function: notify-sla-breach
 *
 * Validates the core logic of grouping SLA breaches by organization,
 * fetching TENANT_ADMIN emails, sending notifications via Resend,
 * and idempotently logging to system_audit_log.
 *
 * Run with: deno test --no-check --allow-env --allow-net supabase/functions/tests/notify_sla_breach_unit_test.ts
 */

import { assertEquals } from "jsr:@std/assert@1";
import { handler } from "../notify-sla-breach/index.ts";

function createMockSupabase(
  mockFacts: any[],
  mockAlreadySent: any[],
  mockOrgName: string,
  mockAdminRoles: any[],
  mockUsersData: any
): any {
  return {
    from: (table: string) => {
      if (table === "sla_audit_ledger_v2") {
        return {
          select: () => ({
            eq: () => ({
              order: () => ({
                limit: async () => ({ data: mockFacts, error: null })
              })
            })
          })
        };
      }
      if (table === "system_audit_log") {
        return {
          select: () => ({
            eq: () => ({
              in: async () => ({ data: mockAlreadySent, error: null })
            })
          }),
          insert: async () => ({ data: null, error: null })
        };
      }
      if (table === "organizations") {
        return {
          select: () => ({
            eq: () => ({
              maybeSingle: async () => ({ data: { name: mockOrgName }, error: null })
            })
          })
        };
      }
      if (table === "user_roles") {
        return {
          select: () => ({
            eq: () => ({
              eq: () => ({
                eq: async () => ({ data: mockAdminRoles, error: null })
              })
            })
          })
        };
      }
      return {};
    },
    auth: {
      admin: {
        getUserById: async (id: string) => ({ data: { user: mockUsersData[id] }, error: null })
      }
    }
  };
}

Deno.test("notify-sla-breach rejects unauthorized requests", async () => {
  const req = new Request("https://example.com/notify-sla-breach", {
    method: "POST",
    headers: { "Content-Type": "application/json" } // No Authorization header
  });

  const response = await handler(req);
  assertEquals(response.status, 401);
});

Deno.test("notify-sla-breach returns 200 with 0 notified if no facts", async () => {
  Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "fake-service-key");
  const req = new Request("https://example.com/notify-sla-breach", {
    method: "POST",
    headers: { "Authorization": "Bearer fake-service-key" }
  });

  const supabase = createMockSupabase([], [], "", [], {});
  const response = await handler(req, supabase, {});
  
  assertEquals(response.status, 200);
  const data = await response.json();
  assertEquals(data.notified, 0);
});

Deno.test("notify-sla-breach skips already notified facts", async () => {
  Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "fake-service-key");
  Deno.env.set("RESEND_API_KEY", "fake-resend-key");
  
  const req = new Request("https://example.com/notify-sla-breach", {
    method: "POST",
    headers: { "Authorization": "Bearer fake-service-key" }
  });

  const mockFactId = crypto.randomUUID();
  const mockFacts = [{
    id: mockFactId,
    organization_id: crypto.randomUUID(),
    payload: { queue_entry_id: "q-1", days_overdue: 2 },
    occurred_at_utc: new Date().toISOString()
  }];

  // Mock system_audit_log showing this fact was already notified
  const mockAlreadySent = [{ payload: { ledger_fact_id: mockFactId } }];

  const supabase = createMockSupabase(mockFacts, mockAlreadySent, "Test Org", [], {});
  const response = await handler(req, supabase, {});
  
  assertEquals(response.status, 200);
  const data = await response.json();
  assertEquals(data.message, "All facts already notified");
  assertEquals(data.notified, 0);
});

Deno.test("notify-sla-breach groups facts and sends emails", async () => {
  Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "fake-service-key");
  Deno.env.set("RESEND_API_KEY", "fake-resend-key");
  Deno.env.set("HMAC_SECRET_KEY_V1", "12345678901234567890123456789012");
  
  const req = new Request("https://example.com/notify-sla-breach", {
    method: "POST",
    headers: { "Authorization": "Bearer fake-service-key" }
  });

  const orgId = crypto.randomUUID();
  const userId = crypto.randomUUID();
  const mockFacts = [
    {
      id: crypto.randomUUID(),
      organization_id: orgId,
      payload: { queue_entry_id: "q-1", days_overdue: 2 },
      occurred_at_utc: new Date().toISOString()
    },
    {
      id: crypto.randomUUID(),
      organization_id: orgId,
      payload: { queue_entry_id: "q-2", days_overdue: 5 },
      occurred_at_utc: new Date().toISOString()
    }
  ];

  const mockAdminRoles = [{ user_id: userId }];
  const mockUsersData = {
    [userId]: { email: "admin@test.com" }
  };

  const supabase = createMockSupabase(mockFacts, [], "Test Org", mockAdminRoles, mockUsersData);

  let sentEmails = 0;
  const resend = {
    emails: {
      send: async () => {
        sentEmails++;
        return { data: { id: "resend-id" }, error: null };
      }
    }
  };

  const response = await handler(req, supabase, resend);
  
  assertEquals(response.status, 200);
  const data = await response.json();
  assertEquals(data.ok, true);
  assertEquals(data.notified, 2); // 2 facts notified
  assertEquals(sentEmails, 1); // 1 email sent for the whole org
});

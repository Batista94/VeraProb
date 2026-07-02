import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert";
import { handler, RESEND_API_URL } from "../dispatch-carrier-notifications/index.ts";

Deno.test("dispatch-carrier-notifications - Unauthenticated Kick", async () => {
  const req = new Request("http://localhost", { method: "POST" });
  const mockCtx = {} as any;
  const mockSupabase = {} as any;
  const res = await handler(mockCtx, mockSupabase, req);
  assertEquals(res.status, 401);
});

Deno.test("dispatch-carrier-notifications - Missing API Key", async () => {
  const req = new Request("http://localhost", {
    method: "POST",
    headers: { "Authorization": "Bearer test-service-role" }
  });
  
  const originalEnvGet = Deno.env.get;
  Deno.env.get = (key: string) => {
    if (key === "SUPABASE_SERVICE_ROLE_KEY") return "test-service-role";
    if (key === "RESEND_API_KEY") return undefined; // Missing key
    return originalEnvGet(key);
  };

  const mockCtx = {} as any;
  const mockSupabase = {} as any;
  const res = await handler(mockCtx, mockSupabase, req);
  assertEquals(res.status, 500);
  
  Deno.env.get = originalEnvGet;
});

Deno.test("dispatch-carrier-notifications - Success (2xx from Resend)", async () => {
  const originalFetch = globalThis.fetch;
  let fetchCalled = false;
  let fetchBody: any = null;

  try {
    globalThis.fetch = async (url: string | URL | Request, init?: RequestInit): Promise<Response> => {
      fetchCalled = true;
      if (init && init.body) {
        fetchBody = JSON.parse(init.body as string);
      }
      return new Response(JSON.stringify({ id: "resend-id-123" }), { status: 200 });
    };

    const mockSupabase = {
      rpc: async (fn: string, args: any) => {
        if (fn === "drain_pending_carrier_notifications") {
          return {
            data: [{
              id: "test-notif-1",
              org_id_out: "org-123",
              ledger_entry_id: "ledg-456",
              carrier_email: "test@carrier.com",
              event_type: "VERDICT_SEALED",
              verdict_outcome: "SEALED",
              fine_cents: 125050, // 1250.50
              portal_token: "token-789"
            }],
            error: null
          };
        }
        return { data: null, error: null };
      },
      from: (table: string) => {
        if (table === "carrier_notification_outbox") {
          return {
            update: (updates: any) => ({
              eq: async () => {
                assertEquals(updates.status, "SENT");
                assertEquals(updates.resend_message_id, "resend-id-123");
                return { error: null };
              }
            })
          };
        }
      }
    } as any;

    const mockCtx = {} as any;
    
    const originalEnvGet = Deno.env.get;
    Deno.env.get = (key: string) => {
      if (key === "SUPABASE_SERVICE_ROLE_KEY") return "test-service-role";
      if (key === "RESEND_API_KEY") return "test-resend-key";
      return originalEnvGet(key);
    };

    const req = new Request("http://localhost", {
      method: "POST",
      headers: { "Authorization": "Bearer test-service-role" }
    });

    const res = await handler(mockCtx, mockSupabase, req);
    assertEquals(res.status, 200);
    assert(fetchCalled, "Fetch should be called");
    
    // Verify payload shaping
    assertEquals(fetchBody.to[0], "test@carrier.com");
    assertEquals(fetchBody.headers["X-Entity-Ref-ID"], "ledg-456");
    assertStringIncludes(fetchBody.text, "R$ 1.250,50");
    assertStringIncludes(fetchBody.html, "https://portal.veraprob.com/disputa/token-789");

    Deno.env.get = originalEnvGet;
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("dispatch-carrier-notifications - Resend Failure triggers backoff", async () => {
  const originalFetch = globalThis.fetch;

  try {
    globalThis.fetch = async (): Promise<Response> => {
      return new Response("Too Many Requests", { status: 429 });
    };

    const mockSupabase = {
      rpc: async (fn: string, args: any) => {
        if (fn === "drain_pending_carrier_notifications") {
          return {
            data: [{
              id: "test-notif-2",
              org_id_out: "org-123",
              ledger_entry_id: "ledg-456",
              carrier_email: "test@carrier.com",
              event_type: "VERDICT_SEALED",
              verdict_outcome: "SEALED",
              fine_cents: 0,
              portal_token: null
            }],
            error: null
          };
        }
        if (fn === "carrier_notification_fail") {
          assertEquals(args.p_notification_id, "test-notif-2");
          assertStringIncludes(args.p_error, "HTTP_429");
          return { error: null };
        }
        return { data: null, error: null };
      }
    } as any;

    const mockCtx = {} as any;
    
    const originalEnvGet = Deno.env.get;
    Deno.env.get = (key: string) => {
      if (key === "SUPABASE_SERVICE_ROLE_KEY") return "test-service-role";
      if (key === "RESEND_API_KEY") return "test-resend-key";
      return originalEnvGet(key);
    };

    const req = new Request("http://localhost", {
      method: "POST",
      headers: { "Authorization": "Bearer test-service-role" }
    });

    const res = await handler(mockCtx, mockSupabase, req);
    assertEquals(res.status, 200); // the function itself succeeds, it just records the error

    Deno.env.get = originalEnvGet;
  } finally {
    globalThis.fetch = originalFetch;
  }
});

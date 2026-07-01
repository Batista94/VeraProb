import { assert, assertEquals } from "jsr:@std/assert";
import { handler } from "../dispatch-verdict-webhooks/index.ts";
import { deriveOrgKey, signWithDerivedKey } from "../shared/hmac_signer.ts";

Deno.test("hmac per-org derivation - deterministic", async () => {
  Deno.env.set("HMAC_SECRET_KEY_V1", "master-test-key");
  const a = await signWithDerivedKey(await deriveOrgKey("org-123", 1), "1700000000.{}");
  const b = await signWithDerivedKey(await deriveOrgKey("org-123", 1), "1700000000.{}");
  assertEquals(a, b);
});

Deno.test("hmac per-org derivation - org isolation (INV-28)", async () => {
  Deno.env.set("HMAC_SECRET_KEY_V1", "master-test-key");
  const sigA = await signWithDerivedKey(await deriveOrgKey("org-A", 1), "msg");
  const sigB = await signWithDerivedKey(await deriveOrgKey("org-B", 1), "msg");
  assert(sigA !== sigB, "different orgs must produce different signatures");
});

Deno.test("hmac per-org derivation - version isolation (V3 rotation)", async () => {
  Deno.env.set("HMAC_SECRET_KEY_V1", "master-test-key");
  const v1 = await signWithDerivedKey(await deriveOrgKey("org-A", 1), "msg");
  const v2 = await signWithDerivedKey(await deriveOrgKey("org-A", 2), "msg");
  assert(v1 !== v2, "key version bump must change the signature");
});

Deno.test("dispatch-verdict-webhooks - Reject SSRF Private IP", async () => {
  const originalResolveDns = Deno.resolveDns;
  try {
    Deno.resolveDns = async (query: string, recordType?: any, options?: any): Promise<any> => {
      if (recordType === "A") return ["10.0.0.1"]; // Private IP
      return [];
    };

    const mockSupabase = {
      rpc: async (fn: string, args: any) => {
        if (fn === "drain_pending_webhooks") {
          return {
            data: [{
              id: "test-log-1",
              org_id_out: "org-123",
              payload: { evidence_hash: "abcd" },
              endpoint_url: "https://example.com/webhook",
              signing_version: 1
            }],
            error: null
          };
        }
        return { data: null, error: null };
      },
      from: (table: string) => ({
        select: () => ({
          eq: () => ({
            eq: () => ({
              maybeSingle: async () => ({ data: null, error: null })
            })
          })
        }),
        // `.eq` is both chainable (rate-limit update filters org + is_active) and awaitable
        // (DEAD update filters id only). Return a Promise that also carries an `.eq`.
        update: (updates: any) => {
          const chain = (): any => {
            const p: any = Promise.resolve().then(() => {
              if (updates.status === "DEAD") {
                assertEquals(updates.last_error, "SSRF_BLOCKED");
              }
              return { error: null };
            });
            p.eq = () => chain();
            return p;
          };
          return { eq: () => chain() };
        }
      })
    } as any;

    const mockCtx = {
      correlationId: "corr-1",
      edgeFunction: "dispatch",
      requestIp: "127.0.0.1",
      orgId: "org-123"
    };

    const originalEnvGet = Deno.env.get;
    Deno.env.get = (key: string) => {
      if (key === "SUPABASE_SERVICE_ROLE_KEY") return "test-service-role";
      if (key === "HMAC_SECRET_KEY_V1") return "mock-master-key";
      return originalEnvGet(key);
    };

    const req = new Request("http://localhost", {
      method: "POST",
      headers: { "Authorization": "Bearer test-user-jwt" }
    });

    const res = await handler(mockCtx, mockSupabase, req);
    assertEquals(res.status, 200);

    Deno.env.get = originalEnvGet;
  } finally {
    Deno.resolveDns = originalResolveDns;
  }
});

Deno.test("dispatch-verdict-webhooks - Rate Limit 429", async () => {
  const mockSupabase = {
    from: (table: string) => ({
      select: () => ({
        eq: () => ({
          eq: () => ({
            maybeSingle: async () => {
              return { data: { last_kick_at: new Date().toISOString() }, error: null };
            }
          })
        })
      }),
      update: () => ({
        eq: async () => ({ error: null })
      })
    }),
    rpc: async () => ({ data: [], error: null })
  } as any;

  const mockCtx = { orgId: "org-123" } as any;

  const req = new Request("http://localhost", {
    method: "POST",
    headers: { "Authorization": "Bearer test-user-jwt" }
  });

  const res = await handler(mockCtx, mockSupabase, req);
  assertEquals(res.status, 429);
});

Deno.test("dispatch-verdict-webhooks - Cross-Verify Tampering (V4)", async () => {
  const originalResolveDns = Deno.resolveDns;
  try {
    Deno.resolveDns = async (): Promise<any> => ["8.8.8.8"]; // Public IP

    const mockSupabase = {
      rpc: async (fn: string) => {
        if (fn === "drain_pending_webhooks") {
          return {
            data: [{
              id: "test-log-2",
              org_id_out: "org-123",
              payload: {
                case: { ledger_entry_id: "led-1" },
                financial: { fine_cents: 100 }
              },
              endpoint_url: "https://example.com/webhook",
              signing_version: 1
            }],
            error: null
          };
        }
        return { data: null, error: null };
      },
      from: (table: string) => {
        if (table === "webhook_delivery_logs") {
          return {
            update: (updates: any) => ({
              eq: async () => {
                assertEquals(updates.status, "DEAD");
                assertEquals(updates.last_error, "PAYLOAD_TAMPERED");
                return { error: null };
              }
            })
          };
        } else if (table === "system_audit_log") {
          return {
            insert: async (data: any) => {
              assertEquals(data.event_type, "PAYLOAD_TAMPERED");
              return { error: null };
            }
          };
        } else if (table === "sla_audit_ledger_v2") {
          // Immutable ledger holds a DIFFERENT sealed fine → payload was tampered.
          return {
            select: () => ({
              eq: () => ({
                eq: () => ({
                  maybeSingle: async () => ({ data: { payload: { verdict_evidence: { fine_cents: 999 } } }, error: null })
                })
              })
            })
          };
        }
      }
    } as any;

    const mockCtx = { orgId: "org-123" } as any;
    
    const originalEnvGet = Deno.env.get;
    Deno.env.get = (key: string) => {
      if (key === "SUPABASE_SERVICE_ROLE_KEY") return "test-service-role";
      if (key === "HMAC_SECRET_KEY_V1") return "mock-master-key";
      return originalEnvGet(key);
    };

    const req = new Request("http://localhost", {
      method: "POST",
      headers: { "Authorization": "Bearer test-service-role" } // Cron bypasses rate limit
    });

    const res = await handler(mockCtx, mockSupabase, req);
    assertEquals(res.status, 200);

    Deno.env.get = originalEnvGet;
  } finally {
    Deno.resolveDns = originalResolveDns;
  }
});

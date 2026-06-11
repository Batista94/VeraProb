/**
 * Unit Tests for Edge Function: verify-evidence-hash
 *
 * Validates the core logic of recomputing the evidence hash and calling
 * the verify_evidence_hash RPC, including org-scope enforcement and
 * security rules.
 *
 * Run with: deno test --no-check --allow-env --allow-net supabase/functions/tests/verify_evidence_hash_unit_test.ts
 */

import { assertEquals } from "jsr:@std/assert@1";
import type { SecurityContext } from "../shared/handle_with_security.ts";
import { handler } from "../verify-evidence-hash/index.ts";

// Mock Supabase Client
function createMockSupabase(
  mockAttachment: any,
  mockFileData: Uint8Array | null,
  mockRpcResult: any,
  mockRpcError: any = null
): any {
  return {
    from: (table: string) => ({
      select: (fields: string) => ({
        eq: (field1: string, val1: string) => ({
          eq: (field2: string, val2: string) => ({
            maybeSingle: async () => {
              if (mockAttachment) {
                return { data: mockAttachment, error: null };
              }
              return { data: null, error: new Error("Not found") };
            },
          }),
        }),
      }),
    }),
    storage: {
      from: (bucket: string) => ({
        download: async (path: string) => {
          if (mockFileData) {
            // Blob is not natively arrayBuffer returning in this simple mock unless we mock it
            return {
              data: {
                arrayBuffer: async () => mockFileData.buffer,
              },
              error: null,
            };
          }
          return { data: null, error: new Error("Download failed") };
        },
      }),
    },
    rpc: async (fnName: string, args: any) => {
      if (mockRpcError) {
        return { data: null, error: mockRpcError };
      }
      return { data: mockRpcResult, error: null };
    },
  };
}

Deno.test("verify-evidence-hash returns sovereignty error on missing org scope", async () => {
  const req = new Request("https://example.com/verify-evidence-hash", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      attachment_id: crypto.randomUUID(),
      organization_id: crypto.randomUUID(),
    }),
  });

  const ctx: SecurityContext = {
    userId: crypto.randomUUID(),
    orgId: crypto.randomUUID(), // Mismatched orgId
    correlationId: "req-1",
    edgeFunction: "verify-evidence-hash",
    requestIp: "127.0.0.1",
  };

  const supabase = createMockSupabase(null, null, null);
  const response = await handler(ctx, supabase, req);

  assertEquals(response.status, 404);
  const data = await response.json();
  assertEquals(data.error, "Not Found");
});

Deno.test("verify-evidence-hash processes valid evidence successfully", async () => {
  const attachmentId = crypto.randomUUID();
  const orgId = crypto.randomUUID();

  const req = new Request("https://example.com/verify-evidence-hash", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      attachment_id: attachmentId,
      organization_id: orgId,
    }),
  });

  const ctx: SecurityContext = {
    userId: crypto.randomUUID(),
    orgId: orgId, // Matching orgId
    correlationId: "req-2",
    edgeFunction: "verify-evidence-hash",
    requestIp: "127.0.0.1",
  };

  const mockAttachment = {
    id: attachmentId,
    organization_id: orgId,
    storage_path: "evid/file.pdf",
    sha256_hash: "mock-hash",
    verification_status: "PENDING",
    deleted_at: null,
  };

  const mockFileData = new Uint8Array([1, 2, 3, 4]); // some raw bytes
  const mockRpcResult = "VERIFIED";

  const supabase = createMockSupabase(mockAttachment, mockFileData, mockRpcResult);
  const response = await handler(ctx, supabase, req);

  assertEquals(response.status, 200);
  const data = await response.json();
  assertEquals(data.verification_status, "VERIFIED");
  assertEquals(data.attachment_id, attachmentId);
});

Deno.test("verify-evidence-hash returns error if attachment is soft-deleted", async () => {
  const attachmentId = crypto.randomUUID();
  const orgId = crypto.randomUUID();

  const req = new Request("https://example.com/verify-evidence-hash", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      attachment_id: attachmentId,
      organization_id: orgId,
    }),
  });

  const ctx: SecurityContext = {
    userId: crypto.randomUUID(),
    orgId: orgId, // Matching orgId
    correlationId: "req-3",
    edgeFunction: "verify-evidence-hash",
    requestIp: "127.0.0.1",
  };

  const mockAttachment = {
    id: attachmentId,
    organization_id: orgId,
    storage_path: "evid/file.pdf",
    sha256_hash: "mock-hash",
    verification_status: "PENDING",
    deleted_at: new Date().toISOString(), // Soft-deleted
  };

  const supabase = createMockSupabase(mockAttachment, null, null);
  const response = await handler(ctx, supabase, req);

  assertEquals(response.status, 404);
  const data = await response.json();
  assertEquals(data.error, "Not Found");
});

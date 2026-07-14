/**
 * Unit Tests for Edge Function: verify-evidence-hash (deprecated stub)
 * CIA: A — shrink surface; all product methods → sovereignty 404 (INV-26)
 */
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { handler } from "../verify-evidence-hash/index.ts";

Deno.test("verify-evidence-hash POST returns sovereignty 404", async () => {
  const req = new Request("https://example.com/verify-evidence-hash", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      attachment_id: "00000000-0000-0000-0000-000000000001",
      organization_id: "00000000-0000-0000-0000-000000000002",
      path: "secret/path.pdf",
      hash: "deadbeef",
    }),
  });
  const res = await handler(null, null, req);
  assertEquals(res.status, 404);
  const body = await res.json() as { error: string };
  assertEquals(body.error, "Not Found");
});

Deno.test("verify-evidence-hash GET returns sovereignty 404", async () => {
  const req = new Request("https://example.com/verify-evidence-hash", {
    method: "GET",
  });
  const res = await handler(null, null, req);
  assertEquals(res.status, 404);
  const body = await res.json() as { error: string };
  assertEquals(body.error, "Not Found");
});

Deno.test("verify-evidence-hash PUT returns sovereignty 404", async () => {
  const req = new Request("https://example.com/verify-evidence-hash", {
    method: "PUT",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ attachment_id: "x" }),
  });
  const res = await handler(null, null, req);
  assertEquals(res.status, 404);
  const body = await res.json() as { error: string };
  assertEquals(body.error, "Not Found");
});

Deno.test("verify-evidence-hash OPTIONS is CORS preflight (not 200 product)", async () => {
  const req = new Request("https://example.com/verify-evidence-hash", {
    method: "OPTIONS",
  });
  const res = await handler(null, null, req);
  assertEquals(res.status, 200);
  assertEquals(res.headers.get("Access-Control-Allow-Methods"), "POST");
});

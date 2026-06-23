/**
 * Unit tests for Edge Function: auditor-dispute-evidence (Tribunal viewer).
 *
 * Exercises the handler in isolation with an injected SecurityContext +
 * SupabaseClient mock and a crafted JWT:
 *   - RBAC: OPERATOR (and any non-admin/auditor) → 404 parity (INV-26).
 *   - Org-scope: the lookup is filtered by ctx.orgId (INV-1/22).
 *   - Anti-oracle: wrong-role and not-found are byte-identical 404s (INV-26).
 *   - Happy path (AUDITOR): 200 with X-Content-SHA256 + no-store Cache-Control.
 *
 * Run: deno test --no-check --allow-env --allow-net \
 *        supabase/functions/tests/auditor_dispute_evidence_unit_test.ts
 */

import { assertEquals } from "jsr:@std/assert@1";
import { handler } from "../auditor-dispute-evidence/index.ts";
import type { SecurityContext } from "../shared/handle_with_security.ts";

const ORG = "00000000-0000-0000-0000-00000dad9a01";
const ATT = "00000000-0000-0000-0000-00000dad9b01";

function createFakeJwt(payload: Record<string, unknown>): string {
  const header = btoa(JSON.stringify({ alg: "HS256", typ: "JWT" }));
  const body = btoa(JSON.stringify(payload));
  return `${header}.${body}.${btoa("sig")}`;
}

function jwtFor(role: string, org = ORG): string {
  return createFakeJwt({
    sub: "00000000-0000-0000-0000-00000dad9c01",
    exp: Math.floor(Date.now() / 1000) + 3600,
    app_metadata: { org_id: org, role },
  });
}

function getReq(token: string | null, attachmentId = ATT): Request {
  const headers: Record<string, string> = {};
  if (token) headers["Authorization"] = `Bearer ${token}`;
  return new Request(
    `https://edge/auditor-dispute-evidence?attachment_id=${attachmentId}`,
    { method: "GET", headers },
  );
}

function ctxFor(org = ORG): SecurityContext {
  return {
    correlationId: "test",
    edgeFunction: "auditor-dispute-evidence",
    requestIp: "127.0.0.1",
    orgId: org,
  };
}

interface Fixture {
  row?: Record<string, unknown> | null;
  blob?: Uint8Array | null;
}

// deno-lint-ignore no-explicit-any
function mockSupabase(fx: Fixture): { client: any; filters: Record<string, unknown> } {
  const filters: Record<string, unknown> = {};
  const builder = {
    select: () => builder,
    eq: (col: string, val: unknown) => {
      filters[col] = val;
      return builder;
    },
    is: (col: string, val: unknown) => {
      filters[col] = val;
      return builder;
    },
    maybeSingle: async () => ({ data: fx.row ?? null, error: null }),
  };
  const client = {
    from: () => builder,
    storage: {
      from: () => ({
        download: async () => ({
          data: fx.blob === null ? null : new Blob([fx.blob ?? new Uint8Array([1, 2, 3])]),
          error: fx.blob === null ? { message: "not found" } : null,
        }),
      }),
    },
  };
  return { client, filters };
}

function freshRow(over: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    storage_path: `${ORG}/queue/att.jpg`,
    file_name: "foto.jpg",
    mime_type: "image/jpeg",
    sha256_hash: "a".repeat(64),
    organization_id: ORG,
    ...over,
  };
}

// ── RBAC ──────────────────────────────────────────────────────────────────────

Deno.test("OPERATOR role → 404 (RBAC, dispute evidence is auditor-grade)", async () => {
  const { client } = mockSupabase({ row: freshRow() });
  const res = await handler(ctxFor(), client, getReq(jwtFor("OPERATOR")));
  assertEquals(res.status, 404);
  await res.body?.cancel();
});

Deno.test("missing Authorization → 404", async () => {
  const { client } = mockSupabase({ row: freshRow() });
  const res = await handler(ctxFor(), client, getReq(null));
  assertEquals(res.status, 404);
  await res.body?.cancel();
});

Deno.test("non-UUID attachment_id → 404", async () => {
  const { client } = mockSupabase({ row: freshRow() });
  const res = await handler(ctxFor(), client, getReq(jwtFor("AUDITOR"), "nope"));
  assertEquals(res.status, 404);
  await res.body?.cancel();
});

// ── Org isolation (INV-1/22) ───────────────────────────────────────────────────

Deno.test("lookup is scoped to ctx.orgId (INV-1/22)", async () => {
  const { client, filters } = mockSupabase({ row: freshRow() });
  const res = await handler(ctxFor(), client, getReq(jwtFor("AUDITOR")));
  assertEquals(filters["organization_id"], ORG);
  assertEquals(filters["id"], ATT);
  assertEquals(filters["deleted_at"], null);
  await res.body?.cancel();
});

// ── Anti-oracle parity (INV-26) ────────────────────────────────────────────────

Deno.test("wrong-role and not-found are byte-identical 404s (anti-oracle)", async () => {
  const wrongRole = mockSupabase({ row: freshRow() });
  const notFound = mockSupabase({ row: null });

  const r1 = await handler(ctxFor(), wrongRole.client, getReq(jwtFor("OPERATOR")));
  const r2 = await handler(ctxFor(), notFound.client, getReq(jwtFor("AUDITOR")));

  assertEquals(r1.status, r2.status);
  assertEquals(await r1.text(), await r2.text());
});

// ── Happy path ─────────────────────────────────────────────────────────────────

Deno.test("AUDITOR + valid attachment → 200 with seal + no-store cache", async () => {
  const { client } = mockSupabase({ row: freshRow(), blob: new Uint8Array([1, 2, 3, 4]) });
  const res = await handler(ctxFor(), client, getReq(jwtFor("AUDITOR")));
  assertEquals(res.status, 200);
  assertEquals(res.headers.get("X-Content-SHA256"), "a".repeat(64));
  assertEquals(res.headers.get("Cache-Control"), "no-store, no-cache, must-revalidate");
  assertEquals(res.headers.get("Content-Type"), "image/jpeg");
  await res.body?.cancel();
});

Deno.test("TENANT_ADMIN is also authorized → 200", async () => {
  const { client } = mockSupabase({ row: freshRow(), blob: new Uint8Array([9, 9]) });
  const res = await handler(ctxFor(), client, getReq(jwtFor("TENANT_ADMIN")));
  assertEquals(res.status, 200);
  await res.body?.cancel();
});

Deno.test("storage download failure → 404", async () => {
  const { client } = mockSupabase({ row: freshRow(), blob: null });
  const res = await handler(ctxFor(), client, getReq(jwtFor("AUDITOR")));
  assertEquals(res.status, 404);
  await res.body?.cancel();
});

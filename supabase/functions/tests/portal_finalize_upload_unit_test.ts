/**
 * Unit tests for Edge Function: portal-finalize-upload (Sprint A, Phase 2).
 *
 * Exercises the server-side trust boundary in isolation with an injected
 * SupabaseClient and an in-memory quarantine blob:
 *   - Token validation: scope/revoked/expired → 404 parity (INV-26).
 *   - Submission ownership + state → 404 parity.
 *   - Zero-trust re-derivation (INV-9/INV-18): magic-byte mismatch and SHA-256
 *     mismatch each fail the submission (correct kind) and return 422.
 *   - Happy path → 200 { status: PENDING_AUDIT, attachmentId }.
 *
 * Run: deno test --no-check --allow-env --allow-net \
 *        supabase/functions/tests/portal_finalize_upload_unit_test.ts
 */

import { assertEquals } from "jsr:@std/assert@1";
import { handler } from "../portal-finalize-upload/index.ts";

const PNG = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3, 4]);

function uuid(): string {
  return crypto.randomUUID();
}

async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function req(body: unknown): Request {
  return new Request("https://edge/portal-finalize-upload", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
}

interface Fixture {
  tokenRow?: Record<string, unknown> | null;
  submissionRow?: Record<string, unknown> | null;
  blobBytes?: Uint8Array | null;
  registerData?: unknown;
  failCalls: Array<{ kind: string; detail: string }>;
}

function mockSupabase(fx: Fixture): any {
  return {
    from: (table: string) => ({
      select: (_cols: string) => ({
        eq: (_col: string, _val: unknown) => ({
          maybeSingle: async () => ({
            data: table === "dispute_portal_tokens"
              ? (fx.tokenRow ?? null)
              : (fx.submissionRow ?? null),
            error: null,
          }),
        }),
      }),
    }),
    storage: {
      from: (_bucket: string) => ({
        download: async (_path: string) => ({
          data: fx.blobBytes === null ? null : new Blob([fx.blobBytes ?? PNG]),
          error: fx.blobBytes === null ? { message: "not found" } : null,
        }),
        upload: async (_p: string, _b: unknown, _o?: unknown) => ({ error: null }),
      }),
    },
    rpc: async (fn: string, args: any) => {
      if (fn === "fail_portal_submission") {
        fx.failCalls.push({ kind: args.p_kind, detail: args.p_detail });
        return { data: null, error: null };
      }
      if (fn === "register_portal_evidence") {
        return { data: fx.registerData ?? uuid(), error: null };
      }
      return { data: null, error: null };
    },
  };
}

function freshToken(over: Record<string, unknown> = {}): Record<string, unknown> {
  const id = uuid();
  return {
    id,
    organization_id: uuid(),
    queue_entry_id: uuid(),
    token_scope: "submit",
    expires_at_utc: new Date(Date.now() + 3_600_000).toISOString(),
    revoked_at_utc: null,
    ...over,
  };
}

function freshSubmission(
  tokenId: string,
  over: Record<string, unknown> = {},
): Record<string, unknown> {
  return {
    id: uuid(),
    organization_id: uuid(),
    queue_entry_id: uuid(),
    token_id: tokenId,
    quarantine_storage_path: "tok/sub.png",
    mime_type_declared: "image/png",
    sha256_client: "a".repeat(64),
    status: "QUARANTINE",
    file_size_bytes_declared: PNG.length,
    ...over,
  };
}

// ── Method / parse / token guards ────────────────────────────────────────────

Deno.test("non-POST → 404 parity", async () => {
  const res = await handler(
    new Request("https://edge/portal-finalize-upload", { method: "GET" }),
    mockSupabase({ failCalls: [] }),
  );
  assertEquals(res.status, 404);
  await res.body?.cancel();
});

Deno.test("invalid JSON → 400", async () => {
  const res = await handler(req("{bad"), mockSupabase({ failCalls: [] }));
  assertEquals(res.status, 400);
  await res.body?.cancel();
});

Deno.test("non-UUID token/submissionId → 404 parity", async () => {
  const res = await handler(
    req({ token: "nope", submissionId: "nope" }),
    mockSupabase({ failCalls: [] }),
  );
  assertEquals(res.status, 404);
  await res.body?.cancel();
});

Deno.test("token not found → 404 parity", async () => {
  const res = await handler(
    req({ token: uuid(), submissionId: uuid() }),
    mockSupabase({ tokenRow: null, failCalls: [] }),
  );
  assertEquals(res.status, 404);
  await res.body?.cancel();
});

Deno.test("token wrong scope (read) → 404 parity", async () => {
  const tok = freshToken({ token_scope: "read" });
  const res = await handler(
    req({ token: uuid(), submissionId: uuid() }),
    mockSupabase({ tokenRow: tok, failCalls: [] }),
  );
  assertEquals(res.status, 404);
  await res.body?.cancel();
});

Deno.test("token revoked → 404 parity", async () => {
  const tok = freshToken({ revoked_at_utc: new Date().toISOString() });
  const res = await handler(
    req({ token: uuid(), submissionId: uuid() }),
    mockSupabase({ tokenRow: tok, failCalls: [] }),
  );
  assertEquals(res.status, 404);
  await res.body?.cancel();
});

Deno.test("token expired → 404 parity", async () => {
  const tok = freshToken({
    expires_at_utc: new Date(Date.now() - 1000).toISOString(),
  });
  const res = await handler(
    req({ token: uuid(), submissionId: uuid() }),
    mockSupabase({ tokenRow: tok, failCalls: [] }),
  );
  assertEquals(res.status, 404);
  await res.body?.cancel();
});

// ── Submission ownership / state ─────────────────────────────────────────────

Deno.test("submission belongs to a different token → 404 parity", async () => {
  const tok = freshToken();
  const sub = freshSubmission(uuid()); // token_id != tok.id
  const res = await handler(
    req({ token: uuid(), submissionId: sub.id }),
    mockSupabase({ tokenRow: tok, submissionRow: sub, failCalls: [] }),
  );
  assertEquals(res.status, 404);
  await res.body?.cancel();
});

Deno.test("submission not in QUARANTINE → 404 parity", async () => {
  const tok = freshToken();
  const sub = freshSubmission(tok.id as string, { status: "PENDING_AUDIT" });
  const res = await handler(
    req({ token: uuid(), submissionId: sub.id }),
    mockSupabase({ tokenRow: tok, submissionRow: sub, failCalls: [] }),
  );
  assertEquals(res.status, 404);
  await res.body?.cancel();
});

// ── Zero-trust re-derivation (INV-9 / INV-18) ────────────────────────────────

Deno.test("magic-byte mismatch (declared pdf, bytes png) → 422 + MIME_MISMATCH", async () => {
  const tok = freshToken();
  const sub = freshSubmission(tok.id as string, { mime_type_declared: "application/pdf" });
  const fx: Fixture = { tokenRow: tok, submissionRow: sub, blobBytes: PNG, failCalls: [] };
  const res = await handler(req({ token: uuid(), submissionId: sub.id }), mockSupabase(fx));
  assertEquals(res.status, 422);
  assertEquals(fx.failCalls.length, 1);
  assertEquals(fx.failCalls[0].kind, "MIME_MISMATCH");
  await res.body?.cancel();
});

Deno.test("SHA-256 mismatch → 422 + HASH_MISMATCH", async () => {
  const tok = freshToken();
  // Correct mime, but declared client hash will not match server re-hash.
  const sub = freshSubmission(tok.id as string, { sha256_client: "b".repeat(64) });
  const fx: Fixture = { tokenRow: tok, submissionRow: sub, blobBytes: PNG, failCalls: [] };
  const res = await handler(req({ token: uuid(), submissionId: sub.id }), mockSupabase(fx));
  assertEquals(res.status, 422);
  assertEquals(fx.failCalls.length, 1);
  assertEquals(fx.failCalls[0].kind, "HASH_MISMATCH");
  await res.body?.cancel();
});

Deno.test("empty quarantine blob → 422 + REJECTED", async () => {
  const tok = freshToken();
  const sub = freshSubmission(tok.id as string);
  const fx: Fixture = {
    tokenRow: tok,
    submissionRow: sub,
    blobBytes: new Uint8Array(0),
    failCalls: [],
  };
  const res = await handler(req({ token: uuid(), submissionId: sub.id }), mockSupabase(fx));
  assertEquals(res.status, 422);
  assertEquals(fx.failCalls[0].kind, "REJECTED");
  await res.body?.cancel();
});

// ── Happy path ───────────────────────────────────────────────────────────────

Deno.test("valid bytes match declared mime + hash → 200 PENDING_AUDIT", async () => {
  const tok = freshToken();
  const realHash = await sha256Hex(PNG);
  const sub = freshSubmission(tok.id as string, { sha256_client: realHash });
  const attachmentId = uuid();
  const fx: Fixture = {
    tokenRow: tok,
    submissionRow: sub,
    blobBytes: PNG,
    registerData: attachmentId,
    failCalls: [],
  };
  const res = await handler(req({ token: uuid(), submissionId: sub.id }), mockSupabase(fx));
  assertEquals(res.status, 200);
  const json = await res.json();
  assertEquals(json.status, "PENDING_AUDIT");
  assertEquals(json.attachmentId, attachmentId);
  assertEquals(fx.failCalls.length, 0);
});

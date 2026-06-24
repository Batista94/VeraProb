/**
 * Unit tests for Edge Function: portal-submit-request (Sprint A, Phase 1).
 *
 * Exercises the thin orchestrator in isolation with an injected SupabaseClient:
 *   - Fail-fast input validation matrix (token, fileName, mime, size, sha, ref).
 *   - 404 parity (INV-26): scope/state/cap RPC failures are indistinguishable
 *     from a non-existent token (the RPC raises insufficient_privilege → 404).
 *   - 80ms response floor (timing side-channel closure).
 *   - Best-effort per-IP throttle (429).
 *   - Happy path returns { submissionId, signedUrl }.
 *
 * Run: deno test --no-check --allow-env --allow-net \
 *        supabase/functions/tests/portal_submit_request_unit_test.ts
 */

import { assert, assertEquals } from "jsr:@std/assert@1";
import { handler } from "../portal-submit-request/index.ts";

const VALID_SHA = "a".repeat(64);

function uuid(): string {
  return crypto.randomUUID();
}

// A fresh random source IP per request keeps the module-level throttle map from
// bleeding rate-limit state across independent test cases.
function randomIp(): string {
  return `${rnd()}.${rnd()}.${rnd()}.${rnd()}`;
}
function rnd(): number {
  return Math.floor(Math.random() * 255) + 1;
}

interface SubmitBody {
  token?: unknown;
  fileName?: unknown;
  mimeType?: unknown;
  fileSizeBytes?: unknown;
  sha256Client?: unknown;
  justification?: unknown;
  submitterReference?: unknown;
}

const VALID_JUSTIFICATION = "Contesto formalmente a infracao registrada.";

function req(body: SubmitBody | string, ip = randomIp()): Request {
  return new Request("https://edge/portal-submit-request", {
    method: "POST",
    headers: { "Content-Type": "application/json", "x-forwarded-for": ip },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
}

function validBody(over: Partial<SubmitBody> = {}): SubmitBody {
  return {
    token: uuid(),
    fileName: "evidence.pdf",
    mimeType: "application/pdf",
    fileSizeBytes: 1024,
    sha256Client: VALID_SHA,
    justification: VALID_JUSTIFICATION,
    submitterReference: "carrier-ref-1",
    ...over,
  };
}

// Mock SupabaseClient: an RPC that mints a row + a storage signer. rpcError may
// carry a `code` (SQLSTATE): "42501" is a BUSINESS rejection (→ 404); anything
// else is treated as INFRASTRUCTURE (→ 503).
function mockSupabase(opts: {
  rpcData?: unknown;
  rpcError?: { message: string; code?: string; details?: string } | null;
  signedUrl?: string | null;
  signError?: { message: string } | null;
} = {}): any {
  return {
    rpc: async (_fn: string, _args: unknown) => ({
      data: opts.rpcData ?? null,
      error: opts.rpcError ?? null,
    }),
    storage: {
      from: (_bucket: string) => ({
        createSignedUploadUrl: async (_path: string, _o?: unknown) => ({
          data: opts.signedUrl === undefined
            ? { signedUrl: "https://storage/signed/upload" }
            : (opts.signedUrl === null ? null : { signedUrl: opts.signedUrl }),
          error: opts.signError ?? null,
        }),
      }),
    },
  };
}

const happyClient = () =>
  mockSupabase({
    rpcData: [{ submission_id: uuid(), quarantine_path: "tok/id.pdf" }],
  });

// ── Method / parse guards ────────────────────────────────────────────────────

Deno.test("OPTIONS preflight returns CORS headers", async () => {
  const res = await handler(
    new Request("https://edge/portal-submit-request", { method: "OPTIONS" }),
    mockSupabase(),
  );
  assertEquals(res.headers.get("Access-Control-Allow-Methods"), "POST");
  await res.body?.cancel();
});

Deno.test("non-POST → 404 parity", async () => {
  const res = await handler(
    new Request("https://edge/portal-submit-request", { method: "GET" }),
    mockSupabase(),
  );
  assertEquals(res.status, 404);
  await res.body?.cancel();
});

Deno.test("invalid JSON body → 400", async () => {
  const res = await handler(req("{not-json"), mockSupabase());
  assertEquals(res.status, 400);
  await res.body?.cancel();
});

// ── Validation matrix ────────────────────────────────────────────────────────

Deno.test("non-UUID token → 404 parity (no DB touch)", async () => {
  const res = await handler(req(validBody({ token: "not-a-uuid" })), happyClient());
  assertEquals(res.status, 404);
  await res.body?.cancel();
});

Deno.test("empty fileName → 400", async () => {
  const res = await handler(req(validBody({ fileName: "" })), happyClient());
  assertEquals(res.status, 400);
  await res.body?.cancel();
});

Deno.test("over-long fileName (>255) → 400", async () => {
  const res = await handler(req(validBody({ fileName: "a".repeat(256) })), happyClient());
  assertEquals(res.status, 400);
  await res.body?.cancel();
});

Deno.test("unsupported mime → 415", async () => {
  const res = await handler(
    req(validBody({ mimeType: "application/x-msdownload" })),
    happyClient(),
  );
  assertEquals(res.status, 415);
  await res.body?.cancel();
});

Deno.test("non-integer fileSizeBytes → 400", async () => {
  const res = await handler(req(validBody({ fileSizeBytes: 12.5 })), happyClient());
  assertEquals(res.status, 400);
  await res.body?.cancel();
});

Deno.test("zero/negative fileSizeBytes → 400", async () => {
  const res = await handler(req(validBody({ fileSizeBytes: 0 })), happyClient());
  assertEquals(res.status, 400);
  await res.body?.cancel();
});

Deno.test("oversized fileSizeBytes (>10MB) → 413", async () => {
  const res = await handler(
    req(validBody({ fileSizeBytes: 10485761 })),
    happyClient(),
  );
  assertEquals(res.status, 413);
  await res.body?.cancel();
});

Deno.test("malformed sha256Client → 400", async () => {
  const res = await handler(req(validBody({ sha256Client: "deadbeef" })), happyClient());
  assertEquals(res.status, 400);
  await res.body?.cancel();
});

Deno.test("non-string submitterReference → 400 (header/param injection guard)", async () => {
  const res = await handler(
    req(validBody({ submitterReference: { evil: "x" } })),
    happyClient(),
  );
  assertEquals(res.status, 400);
  await res.body?.cancel();
});

Deno.test("absent submitterReference is accepted (optional)", async () => {
  const body = validBody();
  delete body.submitterReference;
  const res = await handler(req(body), happyClient());
  assertEquals(res.status, 200);
  await res.body?.cancel();
});

Deno.test("absent justification → 400 (mandatory testimony)", async () => {
  const body = validBody();
  delete body.justification;
  const res = await handler(req(body), happyClient());
  assertEquals(res.status, 400);
  await res.body?.cancel();
});

// ── 404 parity for BUSINESS RPC failures (INV-26) ────────────────────────────

Deno.test("RPC 42501 (bad scope/state/cap) → 404, DETAIL logged not leaked", async () => {
  const logged: string[] = [];
  const orig = console.error;
  console.error = (...a: unknown[]) => logged.push(a.join(" "));
  try {
    const res = await handler(
      req(validBody()),
      mockSupabase({
        rpcError: {
          message: "Submission rejected.",
          code: "42501",
          details: "PORTAL_SUBMIT_REJECTED:SUBMISSION_CAP_EXCEEDED",
        },
      }),
    );
    assertEquals(res.status, 404);
    assertEquals(await res.json(), { error: "Not Found" });
    assert(
      logged.some((l) => l.includes("PORTAL_SUBMIT_REJECTED:SUBMISSION_CAP_EXCEEDED")),
      "DETAIL token must be logged server-side for SRE triage",
    );
  } finally {
    console.error = orig;
  }
});

Deno.test("RPC empty result set → 404 parity", async () => {
  const res = await handler(req(validBody()), mockSupabase({ rpcData: [] }));
  assertEquals(res.status, 404);
  await res.body?.cancel();
});

// ── 503 for INFRASTRUCTURE failures (post-authorization, opaque) ─────────────

Deno.test("RPC non-42501 error (DB/transport down) → 503, opaque body", async () => {
  const res = await handler(
    req(validBody()),
    mockSupabase({ rpcError: { message: "connection refused", code: "08006" } }),
  );
  assertEquals(res.status, 503);
  assertEquals(await res.json(), { error: "Service temporarily unavailable" });
});

Deno.test("signed-url failure (storage down) → 503, not 404 (infra ≠ business)", async () => {
  const res = await handler(
    req(validBody()),
    mockSupabase({
      rpcData: [{ submission_id: uuid(), quarantine_path: "tok/id.pdf" }],
      signedUrl: null,
      signError: { message: "bucket missing" },
    }),
  );
  assertEquals(res.status, 503);
  assertEquals(await res.json(), { error: "Service temporarily unavailable" });
});

// ── Happy path ───────────────────────────────────────────────────────────────

Deno.test("happy path → 200 { submissionId, signedUrl }", async () => {
  const subId = uuid();
  const res = await handler(
    req(validBody()),
    mockSupabase({
      rpcData: [{ submission_id: subId, quarantine_path: "tok/id.pdf", already_finalized: false }],
      signedUrl: "https://storage/signed/PUT",
    }),
  );
  assertEquals(res.status, 200);
  const json = await res.json();
  assertEquals(json.submissionId, subId);
  assertEquals(json.signedUrl, "https://storage/signed/PUT");
});

// ── Timing floor + throttle ──────────────────────────────────────────────────

Deno.test("80ms response floor closes the timing side-channel", async () => {
  const start = Date.now();
  const res = await handler(req(validBody()), happyClient());
  const elapsed = Date.now() - start;
  assertEquals(res.status, 200);
  assert(elapsed >= 75, `expected >= ~80ms floor, got ${elapsed}ms`);
  await res.body?.cancel();
});

Deno.test("per-IP throttle: 4th rapid request from same IP → 429", async () => {
  const ip = randomIp();
  const client = happyClient();
  let last = 200;
  for (let i = 0; i < 4; i++) {
    const res = await handler(req(validBody(), ip), client);
    last = res.status;
    await res.body?.cancel();
  }
  assertEquals(last, 429);
});

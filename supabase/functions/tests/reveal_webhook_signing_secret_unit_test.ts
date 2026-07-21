import { assertEquals, assertNotEquals } from "@std/assert";
import {
  deriveSecretHex,
  handleReveal,
} from "../reveal-webhook-signing-secret/index.ts";
import { deriveOrgKey } from "../shared/hmac_signer.ts";

// ── Helpers ───────────────────────────────────────────────────────────────────

function hexToBytes(hex: string): Uint8Array {
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < hex.length; i += 2) {
    bytes[i / 2] = parseInt(hex.slice(i, i + 2), 16);
  }
  return bytes;
}

// ── Parity: revealed secret MUST verify drain signatures (Integridade/CIA) ───
//
// Regressão do bug: _getMasterKeyRaw fazia hex-decode do env enquanto
// hmac_signer.loadAllKeys usa TextEncoder (bytes UTF-8). Master divergente →
// secret revelado nunca verificaria a assinatura HMAC do dispatch.

Deno.test("reveal parity - deriveSecretHex equals deriveOrgKey material", async () => {
  Deno.env.set("HMAC_SECRET_KEY_V1", "test-master-key-not-hex");

  const orgId = "11111111-2222-3333-4444-555555555555";
  const version = 3;
  const message = new TextEncoder().encode('{"verdict":"SEALED"}');

  // Assina com a chave que o drain usa (hmac_signer).
  const drainKey = await deriveOrgKey(orgId, version);
  const drainSig = await crypto.subtle.sign("HMAC", drainKey, message);

  // Assina com o material revelado ao ERP (secret_hex).
  const revealedHex = await deriveSecretHex(orgId, version);
  const erpKey = await crypto.subtle.importKey(
    "raw",
    hexToBytes(revealedHex) as BufferSource,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const erpSig = await crypto.subtle.sign("HMAC", erpKey, message);

  assertEquals(
    new Uint8Array(drainSig),
    new Uint8Array(erpSig),
    "secret revelado deve produzir assinatura idêntica à do drain",
  );
});

Deno.test("reveal parity - versions derive distinct keys", async () => {
  Deno.env.set("HMAC_SECRET_KEY_V1", "test-master-key-not-hex");
  const orgId = "11111111-2222-3333-4444-555555555555";
  assertNotEquals(
    await deriveSecretHex(orgId, 1),
    await deriveSecretHex(orgId, 2),
  );
});

Deno.test("reveal parity - orgs derive distinct keys (INV-28)", async () => {
  Deno.env.set("HMAC_SECRET_KEY_V1", "test-master-key-not-hex");
  assertNotEquals(
    await deriveSecretHex("11111111-2222-3333-4444-555555555555", 1),
    await deriveSecretHex("66666666-7777-8888-9999-aaaaaaaaaaaa", 1),
  );
});

// ── RBAC / Anti-Oracle (INV-1, INV-26) ────────────────────────────────────────

Deno.test("reveal RBAC - non-TENANT_ADMIN role gets 404", async () => {
  const req = new Request("http://localhost", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ action: "provision" }),
  });
  // deno-lint-ignore no-explicit-any
  const ctx = { orgId: "org-1", userId: "user-1", role: "VIEWER" } as any;
  // deno-lint-ignore no-explicit-any
  const res = await handleReveal(ctx, {} as any, req);
  assertEquals(res.status, 404);
});

Deno.test("reveal RBAC - missing orgId in context gets 404", async () => {
  const req = new Request("http://localhost", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ action: "provision" }),
  });
  // deno-lint-ignore no-explicit-any
  const ctx = { userId: "user-1", role: "TENANT_ADMIN" } as any;
  // deno-lint-ignore no-explicit-any
  const res = await handleReveal(ctx, {} as any, req);
  assertEquals(res.status, 404);
});

Deno.test("reveal-once - provision with existing active key gets 409", async () => {
  const req = new Request("http://localhost", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ action: "provision" }),
  });
  // deno-lint-ignore no-explicit-any
  const ctx = { orgId: "org-1", userId: "user-1", role: "TENANT_ADMIN" } as any;
  const mockSupabase = {
    from: (_table: string) => ({
      select: (_cols: string) => ({
        eq: () => ({
          eq: () => ({
            maybeSingle: () =>
              Promise.resolve({ data: { id: "key-1", version: 2 } }),
          }),
        }),
      }),
    }),
    // deno-lint-ignore no-explicit-any
  } as any;

  const res = await handleReveal(ctx, mockSupabase, req);
  assertEquals(res.status, 409);
  const body = await res.json();
  assertEquals(body.error, "ALREADY_PROVISIONED");
});

Deno.test("reveal RBAC - direct 'reveal' action is denied (reveal-once)", async () => {
  const req = new Request("http://localhost", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ action: "reveal" }),
  });
  // deno-lint-ignore no-explicit-any
  const ctx = { orgId: "org-1", userId: "user-1", role: "TENANT_ADMIN" } as any;
  // deno-lint-ignore no-explicit-any
  const res = await handleReveal(ctx, {} as any, req);
  assertEquals(res.status, 404);
});

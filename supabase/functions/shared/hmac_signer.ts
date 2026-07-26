/**
 * hmac_signer.ts — HMAC-SHA256 signing and verification with Key Rotation support.
 *
 * **INV-31 (HMAC Zero-Knowledge):**
 * - The HMAC secret key **NEVER** resides in the database or the Flutter client.
 * - Signing occurs EXCLUSIVELY in Edge Functions (Deno runtime).
 * - The database is "blind" — stores only the resulting signature, never the key.
 * - Verification is performed On-Read by calling this module with the same secret.
 *
 * **INV-9 (Evidence Sealing):**
 * The payload is canonicalized (sorted keys + normalized types) BEFORE hashing.
 * This ensures that Dart (insert) and Deno (verification) produce byte-identical
 * input to the HMAC function.
 *
 * **Key Rotation (INV-31-R):**
 * - Supports multiple active keys via versioned signatures.
 * - Signature format: `v{version}|{hex_signature}` (e.g., `v1|a1b2c3...`)
 * - On sign: always uses the LATEST key version.
 * - On verify: iterates all known key versions until a match is found.
 * - Old keys remain valid for verification of historical data until retired.
 *
 * **Usage in Edge Functions:**
 * ```ts
 * import { signPayload, verifyPayload } from "../shared/hmac_signer.ts";
 *
 * // On ingest (sign with latest key):
 * const signature = await signPayload(payload);
 * // => "v2|a1b2c3..." (versioned signature)
 *
 * // On read (verify against any active key):
 * const isValid = await verifyPayload(payload, storedSignature);
 * if (!isValid) throw new IntegrityError("HMAC verification failed");
 * ```
 *
 * **Security:**
 * - Secret keys are read from env vars — never hardcoded.
 * - Key versions are integers ≥ 1. Version 1 is the default if no rotation.
 * - Retired keys must be explicitly removed from config — they don't self-expire.
 * - Constant-time comparison prevents timing side-channel attacks.
 *
 * **Environment Variables:**
 * | Variable | Purpose | Required? |
 * |---|---|---|
 * | `HMAC_SECRET_KEY_V1` | Primary/current key | ✅ Always |
 * | `HMAC_SECRET_KEY_V2` | Rotated key (optional) | ⚠️ During rotation |
 * | `HMAC_SECRET_KEY_V3` | Future rotation (optional) | ⚠️ During rotation |
 * | `HMAC_ACTIVE_KEY_VERSION` | Which version to SIGN with | ❌ Defaults to latest |
 *
 * **Rotation Procedure:**
 * 1. Add `HMAC_SECRET_KEY_V2` to env (keep V1 active)
 * 2. Set `HMAC_ACTIVE_KEY_VERSION=2`
 * 3. New records are signed with V2; old V1 records still verify
 * 4. After audit period, remove `HMAC_SECRET_KEY_V1` from env
 * 5. V1-signed records become unverifiable (expected — plan migration batch job)
 */

import { canonicalJson } from "./canonical_json.ts";

// ── Types ────────────────────────────────────────────────────────────────────

/**
 * Represents an HMAC key with its version identifier.
 */
interface HmacKey {
  version: number;
  raw: Uint8Array;
}

// ── Module-Level Key Cache (Deno Isolate Lifetime) ──────────────────────────

/**
 * In-memory cache of HMAC keys — populated ONCE per Deno isolate lifecycle.
 *
 * **Why this matters:** Deno Edge Functions run in a persistent isolate.
 * Module-level state survives across HTTP requests. Without this cache,
 * every `verifyPayload()` call would re-read `Deno.env.get()` in a loop,
 * adding unnecessary FFI overhead to batch validation.
 *
 * **Cache invalidation:** Only on Deno isolate restart (deploy, env change).
 * Key rotation does NOT require code changes — new keys are picked up on
 * the next deploy (when `supabase functions deploy` reloads the isolate).
 *
 * **Thread safety:** Deno's Edge Functions are single-isolate — no race
 * conditions possible on lazy initialization.
 */
let _cachedKeys: HmacKey[] | null = null;

/**
 * Returns the cached key map, loading from env on first access.
 *
 * **Performance:** O(N) only on cold start. All subsequent calls: O(1).
 * For a batch of 1,000 verifications, env is read exactly once.
 */
function getKeys(): HmacKey[] {
  if (_cachedKeys === null) {
    _cachedKeys = loadAllKeys();
  }
  return _cachedKeys;
}

// ── Key Management ───────────────────────────────────────────────────────────

/**
 * Loads all configured HMAC keys from environment variables.
 *
 * Scans for `HMAC_SECRET_KEY_V1`, `HMAC_SECRET_KEY_V2`, etc.
 * Returns them sorted by version number (ascending).
 *
 * **Called only once per isolate lifecycle** (via `getKeys()` cache).
 *
 * @returns Array of HmacKey objects, sorted by version
 * @throws Error if HMAC_SECRET_KEY_V1 is not set (baseline key required)
 */
function loadAllKeys(): HmacKey[] {
  const keys: HmacKey[] = [];
  let version = 1;

  while (true) {
    const keyStr = Deno.env.get(`HMAC_SECRET_KEY_V${version}`);
    if (!keyStr || keyStr.length === 0) break;

    keys.push({
      version,
      raw: new TextEncoder().encode(keyStr),
    });

    version++;
  }

  if (keys.length === 0) {
    throw new Error(
      "No HMAC keys configured. HMAC_SECRET_KEY_V1 must be set in env. " +
      "This is required for INV-31 (HMAC Zero-Knowledge).",
    );
  }

  return keys; // Already sorted by version (ascending)
}

/**
 * Determines which key version to use for SIGNING.
 *
 * Priority:
 * 1. `HMAC_ACTIVE_KEY_VERSION` env var (explicit override)
 * 2. Highest available key version (default — latest key)
 *
 * @param keys — All loaded keys (from loadAllKeys)
 * @returns The HmacKey to use for signing
 */
function getActiveKey(keys: HmacKey[]): HmacKey {
  const activeVersionStr = Deno.env.get("HMAC_ACTIVE_KEY_VERSION");

  if (activeVersionStr) {
    const activeVersion = parseInt(activeVersionStr, 10);
    if (isNaN(activeVersion)) {
      throw new Error(
        `HMAC_ACTIVE_KEY_VERSION is not a valid number: "${activeVersionStr}"`,
      );
    }

    const key = keys.find((k) => k.version === activeVersion);
    if (!key) {
      throw new Error(
        `HMAC_ACTIVE_KEY_VERSION=${activeVersion} but no key found for that version. ` +
        `Available versions: [${keys.map((k) => k.version).join(", ")}]`,
      );
    }

    return key;
  }

  // Default: use the latest (highest version) key
  return keys[keys.length - 1];
}

// ── Signature Format ─────────────────────────────────────────────────────────

/**
 * Signature format: `v{version}|{hex_signature}`
 *
 * Examples:
 * - `v1|a1b2c3d4e5f6...` (64 hex chars = 32 bytes = SHA-256 output)
 * - `v2|deadbeef1234...`
 *
 * The `v{version}|` prefix is 3-5 chars depending on version number.
 * Total signature length = prefix length + 1 (`|`) + 64 (hex chars).
 *
 * **Backward compatibility:** If a signature has no `v{N}|` prefix, it is
 * assumed to be `v1` (pre-rotation format).
 */
const SIGNATURE_PREFIX_REGEX = /^v(\d+)\|/;

/**
 * Parses a versioned signature into its components.
 *
 * @param signature — e.g., `v2|a1b2c3...` or legacy `a1b2c3...` (assumed v1)
 * @returns `{ version: number, hexSignature: string }`
 */
function parseSignature(signature: string): {
  version: number;
  hexSignature: string;
} {
  const match = signature.match(SIGNATURE_PREFIX_REGEX);
  if (match) {
    return {
      version: parseInt(match[1], 10),
      hexSignature: signature.substring(match[0].length),
    };
  }

  // Legacy format (no version prefix) — assumed v1
  return {
    version: 1,
    hexSignature: signature,
  };
}

/**
 * Creates a versioned signature string.
 *
 * @param version — Key version number
 * @param hexSignature — Raw hex-encoded HMAC-SHA256 output
 * @returns Formatted string: `v{version}|{hex}`
 */
function formatSignature(version: number, hexSignature: string): string {
  return `v${version}|${hexSignature}`;
}

// ── Signing ──────────────────────────────────────────────────────────────────

/**
 * Computes an HMAC-SHA256 signature over a canonical JSON payload.
 *
 * **Pipeline:**
 * 1. Canonicalize the payload (sort keys + normalize types via `canonicalJson`)
 * 2. Encode to UTF-8 bytes
 * 3. Compute HMAC-SHA256 with the ACTIVE key
 * 4. Return versioned hex-encoded signature: `v{N}|{hex}`
 *
 * @param payload — The JSON object to sign (typically an ingest payload or ledger entry)
 * @returns Versioned HMAC-SHA256 signature string (e.g., `v2|a1b2c3d4...`)
 *
 * @example
 * ```ts
 * const payload = { organization_id: "org-123", amount_cents: 5000 };
 * const signature = await signPayload(payload);
 * // => "v2|a1b2c3d4e5f6..." (versioned)
 * ```
 */
export async function signPayload(payload: unknown): Promise<string> {
  const keys = getKeys();
  const activeKey = getActiveKey(keys);

  const canonicalStr = canonicalJson(payload);
  const data = new TextEncoder().encode(canonicalStr);

  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    activeKey.raw as BufferSource,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );

  const signatureBuffer = await crypto.subtle.sign("HMAC", cryptoKey, data);
  const signatureBytes = new Uint8Array(signatureBuffer);

  const hexSignature = Array.from(signatureBytes)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");

  return formatSignature(activeKey.version, hexSignature);
}

// ── Verification ─────────────────────────────────────────────────────────────

/**
 * Verifies an HMAC-SHA256 signature against a canonical JSON payload.
 *
 * **Pipeline:**
 * 1. Parse the version from the stored signature (e.g., `v2|...` → version 2)
 * 2. Load the key for that specific version
 * 3. Canonicalize the payload (same as signing)
 * 4. Compute fresh HMAC-SHA256 with the versioned key
 * 5. Constant-time comparison with the stored signature bytes
 *
 * **Key resolution:** The signature encodes which key version was used to sign it.
 * Verification uses THAT specific key — not the current active key. This enables
 * seamless key rotation: old signatures verify with old keys, new signatures with new keys.
 *
 * **Fallback for legacy signatures:** If the signature has no `v{N}|` prefix,
 * it is assumed to be signed with `v1` key. This ensures zero-downtime migration
 * from the pre-rotation format.
 *
 * @param payload — The JSON object to verify
 * @param signature — Versioned hex-encoded HMAC-SHA256 (e.g., `v2|a1b2c3...`)
 * @returns `true` if the signature is valid for the declared key version, `false` otherwise
 *
 * @example
 * ```ts
 * const isValid = await verifyPayload(payload, "v1|a1b2c3...");
 * // Uses key V1 to verify (signature declares v1)
 *
 * const isValid = await verifyPayload(payload, "v2|deadbeef...");
 * // Uses key V2 to verify (signature declares v2)
 *
 * if (!isValid) {
 *   throw new IntegrityError("Ledger entry has been tampered with");
 * }
 * ```
 */
export async function verifyPayload(
  payload: unknown,
  signature: string,
): Promise<boolean> {
  const keys = getKeys();
  const { version, hexSignature } = parseSignature(signature);

  // Find the key for the declared version
  const key = keys.find((k) => k.version === version);
  if (!key) {
    // Key version not found — this could mean:
    // 1. The key was retired and removed from env (expected)
    // 2. The signature is forged with a fake version number
    // In either case, return false (verification fails)
    return false;
  }

  const canonicalStr = canonicalJson(payload);
  const data = new TextEncoder().encode(canonicalStr);

  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    key.raw as BufferSource,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["verify"],
  );

  const signatureBytes = hexToBytes(hexSignature);

  try {
    return await crypto.subtle.verify(
      "HMAC",
      cryptoKey,
      signatureBytes as BufferSource,
      data,
    );
  } catch {
    return false;
  }
}

// ── Helpers ──────────────────────────────────────────────────────────────────

/**
 * Converts a hex-encoded string to a Uint8Array.
 *
 * @param hex — Hex string (e.g., "a1b2c3...")
 * @returns Byte array
 * @throws Error if the hex string has odd length or invalid characters
 */
function hexToBytes(hex: string): Uint8Array {
  if (hex.length % 2 !== 0) {
    throw new Error(
      `Invalid HMAC signature: hex string has odd length (${hex.length})`,
    );
  }

  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < hex.length; i += 2) {
    const byte = parseInt(hex.substring(i, i + 2), 16);
    if (isNaN(byte)) {
      throw new Error(
        `Invalid HMAC signature: non-hex character at position ${i}`,
      );
    }
    bytes[i / 2] = byte;
  }
  return bytes;
}

// ── Per-Org Key Derivation (INV-28 org isolation, INV-31 zero key at rest) ───
//
// Webhook signing must be per-tenant: leaking one org's outbound key (shared with
// that org's ERP) must never compromise another org or the master. We derive it:
//
//   K_org_vN = HMAC-SHA256(masterKey, organization_id || "|" || N)
//
// derived at sign time. The DB stores ONLY the version metadata (N), never the key
// material. One-wayness of HMAC isolates orgs; the master never leaves env.
//
// ponytail: anchored on key version 1 (the original master). Rotating the master =
// re-issuing every org key (the documented incident path), so a single anchor is
// correct today; revisit only if independent master rotation becomes a requirement.

export async function deriveOrgKey(orgId: string, version: number): Promise<CryptoKey> {
  const derived = await deriveOrgKeyRaw(orgId, version);
  return await crypto.subtle.importKey(
    "raw",
    derived as BufferSource,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
}

/** Hex of org-derived key material (reveal-once / ERP HMAC). Same bytes as deriveOrgKey. */
export async function deriveOrgKeyHex(orgId: string, version: number): Promise<string> {
  const derived = await deriveOrgKeyRaw(orgId, version);
  return Array.from(derived).map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function deriveOrgKeyRaw(orgId: string, version: number): Promise<Uint8Array> {
  const keys = getKeys(); // throws the INV-31 error if no master is configured
  const master = keys.find((k) => k.version === 1) ?? keys[0];
  const masterKey = await crypto.subtle.importKey(
    "raw",
    master.raw as BufferSource,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const derived = await crypto.subtle.sign(
    "HMAC", masterKey, new TextEncoder().encode(`${orgId}|${version}`),
  );
  return new Uint8Array(derived);
}

export async function signWithDerivedKey(key: CryptoKey, message: string): Promise<string> {
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message));
  return Array.from(new Uint8Array(sig)).map((b) => b.toString(16).padStart(2, "0")).join("");
}


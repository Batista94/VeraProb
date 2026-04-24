/**
 * Image Quality Validator Tests (INV-18)
 *
 * Zero-trust: uploaded images are untrusted evidence. Degenerate dimensions
 * or suspiciously small files must be flagged before entering the evidence chain.
 *
 * Run with: deno test --allow-env --allow-net supabase/functions/tests/image_quality_validator_test.ts
 */

import { assertEquals } from "jsr:@std/assert@1";
import { validateImageQuality } from "../shared/image_quality_validator.ts";

// ── Tests ────────────────────────────────────────────────────────────────────

Deno.test("returns null for adequate resolution (1920x1080)", () => {
  const result = validateImageQuality(1920, 1080);
  assertEquals(result, null);
});

Deno.test("returns low_resolution warning for 320x240", () => {
  const result = validateImageQuality(320, 240);
  assertEquals(result?.type, "low_resolution");
});

Deno.test("returns low_resolution warning for 640x479 (edge case just below threshold)", () => {
  const result = validateImageQuality(640, 479);
  assertEquals(result?.type, "low_resolution");
});

Deno.test("returns null for exactly 640x480 (boundary passes)", () => {
  const result = validateImageQuality(640, 480);
  assertEquals(result, null);
});

Deno.test("returns too_small warning for file < 10KB", () => {
  const result = validateImageQuality(1920, 1080, 9_999);
  assertEquals(result?.type, "too_small");
});

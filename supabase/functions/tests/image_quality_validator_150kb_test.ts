/**
 * Image Quality Validator — 150KB band tests (Task 5, INV-9, INV-18)
 *
 * Validates the new low_quality warning band added for evidence quality feedback.
 * Evidence is ALWAYS sealed (SHA-256) regardless of quality. Warning is non-blocking.
 *
 * Run with: deno test --allow-env supabase/functions/tests/image_quality_validator_150kb_test.ts
 */

import { assertEquals, assertNotEquals } from "jsr:@std/assert@1";
import { validateImageQuality } from "../shared/image_quality_validator.ts";

// ── Existing bands (regression guard) ────────────────────────────────────────

Deno.test("below 10KB: returns too_small (existing behavior unchanged)", () => {
  const result = validateImageQuality(1920, 1080, 9_999);
  assertEquals(result?.type, "too_small");
});

Deno.test("exactly 10KB: falls through to 150KB band check", () => {
  // 10_240 bytes = exactly 10KB. Should hit the 150KB band (< 153_600).
  const result = validateImageQuality(1920, 1080, 10_240);
  assertEquals(result?.type, "low_quality");
});

// ── New 150KB band ────────────────────────────────────────────────────────────

Deno.test("10KB to 150KB: returns low_quality warning", () => {
  const result = validateImageQuality(1920, 1080, 100_000);
  assertEquals(result?.type, "low_quality");
  assertNotEquals(result, null);
});

Deno.test("150KB band: message contains 'prova em disputa'", () => {
  const result = validateImageQuality(1920, 1080, 75_000);
  assertEquals(result?.message.includes("prova em disputa"), true);
});

Deno.test("exactly 153599 bytes (150KB - 1): returns low_quality", () => {
  const result = validateImageQuality(1920, 1080, 153_599);
  assertEquals(result?.type, "low_quality");
});

Deno.test("exactly 153600 bytes (150KB): does NOT return low_quality (above threshold)", () => {
  const result = validateImageQuality(1920, 1080, 153_600);
  // Above 150KB — falls through to dimension check. 1920x1080 passes dimension.
  assertEquals(result, null);
});

Deno.test("above 150KB, adequate dimensions: returns null (no warning)", () => {
  const result = validateImageQuality(1920, 1080, 500_000);
  assertEquals(result, null);
});

// ── Dimension check still fires after 150KB threshold ────────────────────────

Deno.test("above 150KB, low dimensions: returns low_resolution", () => {
  const result = validateImageQuality(320, 240, 200_000);
  assertEquals(result?.type, "low_resolution");
});

// ── No fileSize supplied (non-photo media) ────────────────────────────────────

Deno.test("no fileSize: skips size checks, dimension check only", () => {
  const result = validateImageQuality(1920, 1080);
  assertEquals(result, null);
});

Deno.test("no fileSize, low dimensions: returns low_resolution", () => {
  const result = validateImageQuality(320, 240);
  assertEquals(result?.type, "low_resolution");
});

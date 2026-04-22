/**
 * EXIF Extractor Tests (INV-9, INV-18)
 *
 * Evidence chain-of-custody: EXIF metadata extraction must be robust against
 * malformed, spoofed, or non-JPEG inputs. Zero-trust — all bytes are untrusted
 * until parsed and validated.
 *
 * Run with: deno test --allow-env --allow-net supabase/functions/tests/exif_extractor_test.ts
 */

import { assertEquals } from "jsr:@std/assert@1";
import { extractExifMetadata } from "../shared/exif_extractor.ts";

// ── Tests ────────────────────────────────────────────────────────────────────

Deno.test("extractExifMetadata returns null for empty data", () => {
  const result = extractExifMetadata(new Uint8Array(0));
  assertEquals(result, null);
});

Deno.test("extractExifMetadata returns null for PNG (no EXIF)", () => {
  // PNG magic bytes: 89 50 4E 47 0D 0A 1A 0A
  const png = new Uint8Array([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  const result = extractExifMetadata(png);
  assertEquals(result, null);
});

Deno.test("extractExifMetadata returns null for PDF", () => {
  // PDF magic bytes: %PDF
  const pdf = new Uint8Array([0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x34]);
  const result = extractExifMetadata(pdf);
  assertEquals(result, null);
});

Deno.test("extractExifMetadata returns null for JPEG without APP1 (EXIF) segment", () => {
  // Minimal JPEG: SOI (FF D8) + APP0/JFIF marker (FF E0) + minimal length + EOI (FF D9)
  const jpeg = new Uint8Array([
    0xFF, 0xD8,             // SOI
    0xFF, 0xE0,             // APP0 (JFIF, not EXIF)
    0x00, 0x10,             // Length: 16 bytes
    0x4A, 0x46, 0x49, 0x46, 0x00, // "JFIF\0"
    0x01, 0x01,             // Version 1.1
    0x00,                   // Aspect ratio units
    0x00, 0x01,             // X density
    0x00, 0x01,             // Y density
    0x00, 0x00,             // Thumbnail dimensions
    0xFF, 0xD9,             // EOI
  ]);
  const result = extractExifMetadata(jpeg);
  assertEquals(result, null);
});

Deno.test("extractExifMetadata returns null for truncated/corrupt JPEG", () => {
  // SOI only, no segments
  const truncated = new Uint8Array([0xFF, 0xD8]);
  const result = extractExifMetadata(truncated);
  assertEquals(result, null);
});

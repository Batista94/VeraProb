/**
 * Tests for EXIF stripping logic used by secure-evidence-proxy.
 *
 * INV-18: Zero-Trust — EXIF metadata (GPS, device info) must be stripped
 *         before serving evidence to the browser to prevent data leakage.
 * INV-9:  Original evidence in storage is never modified (sealed at ingestion).
 */

import { assertEquals } from "jsr:@std/assert@1";
import { stripExifFromJpeg } from "../shared/exif_stripper.ts";

// ── Helpers ──────────────────────────────────────────────────────────────────

/** Builds a minimal valid JPEG with SOI + optional segments + EOI. */
function buildJpeg(segments: Uint8Array[]): Uint8Array {
  const parts: Uint8Array[] = [new Uint8Array([0xFF, 0xD8])]; // SOI
  parts.push(...segments);
  parts.push(new Uint8Array([0xFF, 0xD9])); // EOI
  const total = parts.reduce((s, p) => s + p.length, 0);
  const out = new Uint8Array(total);
  let offset = 0;
  for (const p of parts) {
    out.set(p, offset);
    offset += p.length;
  }
  return out;
}

/** Creates an APP1 (0xFFE1) segment with given payload bytes. */
function makeApp1(payload: Uint8Array): Uint8Array {
  const len = payload.length + 2; // length field includes itself
  const seg = new Uint8Array(4 + payload.length);
  seg[0] = 0xFF;
  seg[1] = 0xE1;
  seg[2] = (len >> 8) & 0xFF;
  seg[3] = len & 0xFF;
  seg.set(payload, 4);
  return seg;
}

/** Creates a JFIF APP0 (0xFFE0) segment. */
function makeApp0(): Uint8Array {
  const jfif = new TextEncoder().encode("JFIF\0");
  const len = jfif.length + 2;
  const seg = new Uint8Array(4 + jfif.length);
  seg[0] = 0xFF;
  seg[1] = 0xE0;
  seg[2] = (len >> 8) & 0xFF;
  seg[3] = len & 0xFF;
  seg.set(jfif, 4);
  return seg;
}

// ── Tests ────────────────────────────────────────────────────────────────────

Deno.test("stripExifFromJpeg: returns null for non-JPEG input", () => {
  const png = new Uint8Array([0x89, 0x50, 0x4E, 0x47]);
  assertEquals(stripExifFromJpeg(png), null);
});

Deno.test("stripExifFromJpeg: returns original bytes when no APP1 present", () => {
  const jpeg = buildJpeg([makeApp0()]);
  const result = stripExifFromJpeg(jpeg);
  assertEquals(result, jpeg);
});

Deno.test("stripExifFromJpeg: removes single APP1 segment", () => {
  const exifPayload = new TextEncoder().encode("Exif\0\0fake-gps-data");
  const jpeg = buildJpeg([makeApp0(), makeApp1(exifPayload)]);
  const result = stripExifFromJpeg(jpeg)!;

  // Result should not contain 0xFFE1
  let hasApp1 = false;
  for (let i = 0; i < result.length - 1; i++) {
    if (result[i] === 0xFF && result[i + 1] === 0xE1) {
      hasApp1 = true;
      break;
    }
  }
  assertEquals(hasApp1, false);
  // SOI preserved
  assertEquals(result[0], 0xFF);
  assertEquals(result[1], 0xD8);
});

Deno.test("stripExifFromJpeg: removes multiple APP1 segments", () => {
  const exif1 = makeApp1(new TextEncoder().encode("Exif\0\0data1"));
  const exif2 = makeApp1(new TextEncoder().encode("XMP-data-here"));
  const jpeg = buildJpeg([makeApp0(), exif1, exif2]);
  const result = stripExifFromJpeg(jpeg)!;

  let app1Count = 0;
  for (let i = 0; i < result.length - 1; i++) {
    if (result[i] === 0xFF && result[i + 1] === 0xE1) app1Count++;
  }
  assertEquals(app1Count, 0);
});

Deno.test("stripExifFromJpeg: preserves APP0 (JFIF) segment", () => {
  const exifPayload = new TextEncoder().encode("Exif\0\0gps");
  const jpeg = buildJpeg([makeApp0(), makeApp1(exifPayload)]);
  const result = stripExifFromJpeg(jpeg)!;

  // APP0 (0xFFE0) should still be present
  let hasApp0 = false;
  for (let i = 0; i < result.length - 1; i++) {
    if (result[i] === 0xFF && result[i + 1] === 0xE0) {
      hasApp0 = true;
      break;
    }
  }
  assertEquals(hasApp0, true);
});

Deno.test("stripExifFromJpeg: handles truncated segment gracefully", () => {
  // JPEG with SOI + incomplete APP1 (only marker, no length)
  const truncated = new Uint8Array([0xFF, 0xD8, 0xFF, 0xE1]);
  const result = stripExifFromJpeg(truncated);
  // Should not throw — returns null or best-effort
  assertEquals(result !== undefined, true);
});

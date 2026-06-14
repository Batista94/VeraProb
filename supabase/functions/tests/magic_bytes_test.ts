import { assertEquals } from "jsr:@std/assert@1";
import { detectMime, isMimeConsistent, mimeExt } from "../shared/magic_bytes.ts";

function buf(...parts: (number[] | string)[]): Uint8Array {
  const out: number[] = [];
  for (const p of parts) {
    if (typeof p === "string") {
      for (const c of p) out.push(c.charCodeAt(0));
    } else {
      out.push(...p);
    }
  }
  return new Uint8Array(out);
}

Deno.test("detectMime: PDF", () => {
  assertEquals(detectMime(buf("%PDF-1.7")), "application/pdf");
});

Deno.test("detectMime: JPEG", () => {
  assertEquals(detectMime(buf([0xff, 0xd8, 0xff, 0xe0])), "image/jpeg");
});

Deno.test("detectMime: PNG", () => {
  assertEquals(detectMime(buf([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])), "image/png");
});

Deno.test("detectMime: WebP", () => {
  assertEquals(detectMime(buf("RIFF", [0, 0, 0, 0], "WEBP")), "image/webp");
});

Deno.test("detectMime: HEIC ftyp brand", () => {
  assertEquals(detectMime(buf([0, 0, 0, 0x18], "ftyp", "heic")), "image/heic");
});

Deno.test("detectMime: unrecognized → null", () => {
  assertEquals(detectMime(buf([0x4d, 0x5a, 0x90, 0x00])), null); // MZ (exe)
});

Deno.test("detectMime: empty → null", () => {
  assertEquals(detectMime(new Uint8Array(0)), null);
});

Deno.test("isMimeConsistent: exact match", () => {
  assertEquals(isMimeConsistent("application/pdf", "application/pdf"), true);
});

Deno.test("isMimeConsistent: declared pdf but detected jpeg → false (smuggling)", () => {
  assertEquals(isMimeConsistent("application/pdf", "image/jpeg"), false);
});

Deno.test("isMimeConsistent: heic/heif family equivalence", () => {
  assertEquals(isMimeConsistent("image/heif", "image/heic"), true);
});

Deno.test("mimeExt mapping", () => {
  assertEquals(mimeExt("application/pdf"), "pdf");
  assertEquals(mimeExt("image/jpeg"), "jpg");
  assertEquals(mimeExt("image/webp"), "webp");
});

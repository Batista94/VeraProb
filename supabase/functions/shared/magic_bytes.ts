/**
 * Magic-byte content sniffing for portal counter-evidence (INV-18: zero-trust).
 *
 * A carrier-declared Content-Type / mime is never trusted. At finalize the
 * server reads the leading bytes of the uploaded blob and derives the real type.
 * A declared/detected mismatch quarantines the submission (PORTAL_EVIDENCE_MIME_MISMATCH).
 *
 * Supported families mirror chk_pes_mime_declared / chk_evidence_mime:
 *   image/jpeg, image/png, application/pdf, image/heic, image/heif, image/webp
 */

export type DetectedMime =
  | "image/jpeg"
  | "image/png"
  | "application/pdf"
  | "image/heic"
  | "image/heif"
  | "image/webp";

function ascii(bytes: Uint8Array, start: number, len: number): string {
  let s = "";
  for (let i = start; i < start + len && i < bytes.length; i++) {
    s += String.fromCharCode(bytes[i]);
  }
  return s;
}

function startsWith(bytes: Uint8Array, sig: number[]): boolean {
  if (bytes.length < sig.length) return false;
  for (let i = 0; i < sig.length; i++) {
    if (bytes[i] !== sig[i]) return false;
  }
  return true;
}

/**
 * Returns the canonical mime detected from magic bytes, or null if unrecognized.
 */
export function detectMime(bytes: Uint8Array): DetectedMime | null {
  // PDF: "%PDF"
  if (startsWith(bytes, [0x25, 0x50, 0x44, 0x46])) return "application/pdf";

  // JPEG: FF D8 FF
  if (startsWith(bytes, [0xff, 0xd8, 0xff])) return "image/jpeg";

  // PNG: 89 50 4E 47 0D 0A 1A 0A
  if (startsWith(bytes, [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) {
    return "image/png";
  }

  // WebP: "RIFF" .... "WEBP"
  if (ascii(bytes, 0, 4) === "RIFF" && ascii(bytes, 8, 4) === "WEBP") {
    return "image/webp";
  }

  // HEIC/HEIF: ISO-BMFF "ftyp" box at offset 4, brand at offset 8.
  if (ascii(bytes, 4, 4) === "ftyp") {
    const brand = ascii(bytes, 8, 4).toLowerCase();
    if (["heic", "heix", "hevc", "heim", "heis", "hevm", "hevs"].includes(brand)) {
      return "image/heic";
    }
    if (["mif1", "msf1", "heif"].includes(brand)) return "image/heif";
  }

  return null;
}

/**
 * True when the detected content is consistent with the declared mime.
 * HEIC and HEIF share the ISO-BMFF container and brand variants overlap, so
 * they are treated as one family to avoid false mismatches.
 */
export function isMimeConsistent(declared: string, detected: DetectedMime): boolean {
  if (declared === detected) return true;
  const heif = new Set(["image/heic", "image/heif"]);
  return heif.has(declared) && heif.has(detected);
}

/**
 * Canonical mime → file extension (mirrors public.portal_mime_ext in SQL).
 */
export function mimeExt(mime: DetectedMime): string {
  switch (mime) {
    case "image/jpeg":
      return "jpg";
    case "image/png":
      return "png";
    case "application/pdf":
      return "pdf";
    case "image/heic":
      return "heic";
    case "image/heif":
      return "heif";
    case "image/webp":
      return "webp";
  }
}

/**
 * EXIF Stripper — removes APP1 (0xFFE1) segments from JPEG bytes.
 *
 * INV-18: Zero-Trust — EXIF metadata (GPS coordinates, device info, timestamps)
 *         must be stripped before serving evidence to browser clients.
 * INV-9:  Original evidence in storage is NEVER modified. Stripping is done
 *         on-the-fly in the proxy response stream.
 *
 * Only processes JPEG. Returns null for non-JPEG input.
 */

/**
 * Strips all APP1 (0xFFE1) segments from a JPEG byte array.
 * Returns the cleaned bytes, or null if input is not JPEG.
 * Returns the original bytes unchanged if no APP1 segments found.
 */
export function stripExifFromJpeg(bytes: Uint8Array): Uint8Array | null {
  // Validate JPEG SOI marker
  if (bytes.length < 4 || bytes[0] !== 0xFF || bytes[1] !== 0xD8) return null;

  const chunks: Uint8Array[] = [bytes.subarray(0, 2)]; // SOI
  let i = 2;
  let stripped = false;

  while (i < bytes.length - 1) {
    // Not a marker — reached image data, copy rest
    if (bytes[i] !== 0xFF) {
      chunks.push(bytes.subarray(i));
      break;
    }

    const marker = bytes[i + 1];

    // Standalone markers (RST0-RST7, SOI, EOI, TEM)
    if (marker === 0x00 || marker === 0x01 || (marker >= 0xD0 && marker <= 0xD9)) {
      chunks.push(bytes.subarray(i, i + 2));
      i += 2;
      continue;
    }

    // SOS (0xFFDA) — start of scan, rest is entropy-coded data
    if (marker === 0xDA) {
      chunks.push(bytes.subarray(i));
      break;
    }

    // Segment with length field
    if (i + 3 >= bytes.length) {
      // Truncated — copy remainder as-is
      chunks.push(bytes.subarray(i));
      break;
    }

    const segLen = (bytes[i + 2] << 8) | bytes[i + 3];
    const segEnd = i + 2 + segLen;

    if (marker === 0xE1) {
      // APP1 — skip (strip EXIF/XMP)
      stripped = true;
      i = segEnd;
      continue;
    }

    // Keep all other segments
    chunks.push(bytes.subarray(i, Math.min(segEnd, bytes.length)));
    i = segEnd;
  }

  if (!stripped) return bytes;

  // Reassemble
  const total = chunks.reduce((s, c) => s + c.length, 0);
  const out = new Uint8Array(total);
  let offset = 0;
  for (const c of chunks) {
    out.set(c, offset);
    offset += c.length;
  }
  return out;
}

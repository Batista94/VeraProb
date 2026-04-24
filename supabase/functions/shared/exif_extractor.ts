/**
 * EXIF Metadata Extractor (INV-9, INV-18)
 *
 * Best-effort extraction from raw image bytes.
 * NEVER throws — returns null on any failure (corrupt, non-JPEG, etc.).
 * All telemetry is untrusted until normalized (INV-18).
 */

import ExifReader from "npm:exifreader@4.23.5";

export interface ExifMetadata {
  gps_latitude: number | null;  // Physical Metric - Double Required
  gps_longitude: number | null; // Physical Metric - Double Required
  make: string | null;
  model: string | null;
  date_time_original: string | null;
}

/**
 * Extracts EXIF metadata from raw image bytes.
 *
 * @param bytes - Raw file bytes (Uint8Array)
 * @returns Parsed EXIF metadata or null if extraction fails
 */
export function extractExifMetadata(bytes: Uint8Array): ExifMetadata | null {
  try {
    if (bytes.length === 0) return null;

    const tags = ExifReader.load(bytes.buffer);

    const lat = tags.GPSLatitude?.description;
    const lon = tags.GPSLongitude?.description;

    return {
      gps_latitude: lat !== undefined ? Number(lat) || null : null,
      gps_longitude: lon !== undefined ? Number(lon) || null : null,
      make: tags.Make?.description ?? null,
      model: tags.Model?.description ?? null,
      date_time_original: tags.DateTimeOriginal?.description ?? null,
    };
  } catch {
    return null;
  }
}

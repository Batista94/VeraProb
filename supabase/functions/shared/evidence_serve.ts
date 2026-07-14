/**
 * Download storage object, strip JPEG EXIF, return binary Response.
 * Callers own authz / row lookup before invoking.
 */
import { stripExifFromJpeg } from "./exif_stripper.ts";
import { mimeFromExt } from "./mime.ts";
import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { sovereigntyErrorResponse } from "./sovereignty_error_mapper.ts";

export async function serveEvidenceBytes(opts: {
  supabase: SupabaseClient;
  bucket: string;
  storagePath: string;
  fileName: string | null | undefined;
  mimeType?: string | null;
}): Promise<Response> {
  const { data: fileData, error: dlError } = await opts.supabase.storage
    .from(opts.bucket)
    .download(opts.storagePath);

  if (dlError || !fileData) return sovereigntyErrorResponse();

  const bytes = new Uint8Array(await fileData.arrayBuffer());
  const fileName = opts.fileName ?? "evidence";
  const ext = fileName.split(".").pop()?.toLowerCase() ?? "";
  const contentType = opts.mimeType ?? mimeFromExt(ext);

  let responseBytes: Uint8Array = bytes;
  if (ext === "jpg" || ext === "jpeg") {
    const stripped = stripExifFromJpeg(bytes);
    if (stripped) responseBytes = stripped;
  }

  return new Response(responseBytes, {
    status: 200,
    headers: {
      "Content-Type": contentType,
      "Content-Disposition": `inline; filename="${fileName}"`,
      "Cache-Control": "private, max-age=300",
      "X-Content-Type-Options": "nosniff",
    },
  });
}

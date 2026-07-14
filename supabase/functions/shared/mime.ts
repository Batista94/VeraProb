/** MIME from file extension — shared by evidence proxies. */
export function mimeFromExt(ext: string): string {
  const map: Record<string, string> = {
    jpg: "image/jpeg",
    jpeg: "image/jpeg",
    png: "image/png",
    pdf: "application/pdf",
    mp4: "video/mp4",
    webp: "image/webp",
    heic: "image/heic",
    ogg: "audio/ogg",
  };
  return map[ext] ?? "application/octet-stream";
}

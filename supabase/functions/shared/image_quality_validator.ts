/**
 * Image Quality Validator (INV-18)
 *
 * Zero-trust: flags degenerate dimensions or suspiciously small files
 * before they enter the evidence chain.
 */

export interface QualityWarning {
  type: "low_resolution" | "too_small" | "low_quality";
  message: string;
}

/**
 * Validates image quality based on dimensions and file size.
 *
 * @param width - Image width in pixels
 * @param height - Image height in pixels
 * @param fileSize - Optional file size in bytes
 * @returns Warning if quality is insufficient, null otherwise
 */
export function validateImageQuality(
  width: number,
  height: number,
  fileSize?: number,
): QualityWarning | null {
  if (fileSize !== undefined && fileSize < 10_240) {
    return { type: "too_small", message: "Arquivo muito pequeno (< 10KB). A qualidade pode ser insuficiente para uso como evidência." };
  }
  if (fileSize !== undefined && fileSize < 153_600) {
    return { type: "low_quality", message: "Resolução baixa — pode não servir como prova em disputa. Reenvie mais nítida." };
  }
  if (width < 640 || height < 480) {
    return { type: "low_resolution", message: "Resolução baixa. Recomendado: mínimo 640x480 para evidência forense." };
  }
  return null;
}

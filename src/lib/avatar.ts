export const AVATAR_BUCKET = "avatars";
export const AVATAR_MAX_INPUT_BYTES = 8 * 1024 * 1024;
export const AVATAR_ALLOWED_TYPES = ["image/jpeg", "image/png", "image/webp"] as const;
export const AVATAR_MIN_SIDE = 96;
export const AVATAR_MAX_SIDE = 8000;
export const AVATAR_OUTPUT_SIDE = 512;

export function validateAvatarFile(file: { type: string; size: number }): string | null {
  if (!(AVATAR_ALLOWED_TYPES as readonly string[]).includes(file.type)) return "Use uma imagem JPG, PNG ou WebP.";
  if (file.size > AVATAR_MAX_INPUT_BYTES) return "A imagem pode ter no máximo 8 MB.";
  if (file.size === 0) return "Arquivo vazio.";
  return null;
}
export function validateAvatarDimensions(w: number, h: number): string | null {
  if (w < AVATAR_MIN_SIDE || h < AVATAR_MIN_SIDE) return `A imagem precisa ter pelo menos ${AVATAR_MIN_SIDE}x${AVATAR_MIN_SIDE} pixels.`;
  if (w > AVATAR_MAX_SIDE || h > AVATAR_MAX_SIDE) return `A imagem pode ter no máximo ${AVATAR_MAX_SIDE} pixels de lado.`;
  return null;
}

/** avatar_url may hold a storage path (new) or an old public URL; return the object path. */
export function avatarObjectPath(value: string | null | undefined): string | null {
  if (!value) return null;
  const marker = `/object/public/${AVATAR_BUCKET}/`;
  const i = value.indexOf(marker);
  if (i >= 0) return decodeURIComponent(value.slice(i + marker.length).split("?")[0] ?? "");
  if (/^https?:/.test(value)) return null;
  return value;
}

export function initials(name: string | null | undefined, email?: string | null): string {
  const src = (name || email || "?").trim();
  const parts = src.split(/[\s._-]+/).filter(Boolean);
  const s = parts.length > 1 ? `${parts[0]![0]}${parts[1]![0]}` : src.slice(0, 2);
  return s.toUpperCase();
}

/** Square crop + resize to WebP in the browser. */
export async function processAvatar(file: File): Promise<Blob> {
  const bmp = await createImageBitmap(file).catch(() => { throw new Error("Não foi possível ler essa imagem."); });
  const dim = validateAvatarDimensions(bmp.width, bmp.height);
  if (dim) { bmp.close(); throw new Error(dim); }
  const side = Math.min(bmp.width, bmp.height);
  const out = Math.min(AVATAR_OUTPUT_SIDE, side);
  const canvas = document.createElement("canvas");
  canvas.width = out; canvas.height = out;
  const ctx = canvas.getContext("2d");
  if (!ctx) throw new Error("Seu navegador não conseguiu processar a imagem.");
  ctx.imageSmoothingQuality = "high";
  ctx.drawImage(bmp, (bmp.width - side) / 2, (bmp.height - side) / 2, side, side, 0, 0, out, out);
  bmp.close();
  const blob = await new Promise<Blob | null>(r => canvas.toBlob(r, "image/webp", 0.85));
  if (blob && blob.type === "image/webp") return blob;
  const jpg = await new Promise<Blob | null>(r => canvas.toBlob(r, "image/jpeg", 0.85));
  if (!jpg) throw new Error("Falha ao comprimir a imagem.");
  return jpg;
}

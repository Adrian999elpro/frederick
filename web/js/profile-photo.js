import { sb } from "./core.js?v=20261018-community";

const BUCKET = "profile-photos";
export async function profilePhotoUrl(userId) {
  const { data, error } = await sb.storage.from(BUCKET).list(userId, { search: "avatar", limit: 1 });
  if (error) throw error;
  if (!data?.some(file => file.name === "avatar")) return null;
  const result = await sb.storage.from(BUCKET).createSignedUrl(`${userId}/avatar`, 60);
  if (result.error) throw result.error;
  return result.data.signedUrl;
}

export async function saveProfilePhoto(userId, file) {
  if (!file || !["image/jpeg", "image/png", "image/webp"].includes(file.type)) {
    throw new Error("Elige una imagen JPG, PNG o WebP.");
  }
  if (file.size > 5 * 1024 * 1024) throw new Error("La foto debe pesar como máximo 5 MB.");
  const bitmap = await createImageBitmap(file);
  try {
    const canvas = document.createElement("canvas");
    canvas.width = canvas.height = 512;
    const size = Math.min(bitmap.width, bitmap.height);
    const ctx = canvas.getContext("2d");
    ctx.fillStyle = "#ffffff";
    ctx.fillRect(0, 0, 512, 512);
    ctx.drawImage(bitmap, (bitmap.width-size)/2, (bitmap.height-size)/2, size, size, 0, 0, 512, 512);
    const blob = await new Promise(resolve => canvas.toBlob(resolve, "image/jpeg", .85));
    if (!blob) throw new Error("No se pudo preparar la imagen.");
    const { error } = await sb.storage.from(BUCKET).upload(`${userId}/avatar`, blob, { upsert: true, contentType: "image/jpeg", cacheControl: "0" });
    if (error) throw error;
  } finally { bitmap.close(); }
  return profilePhotoUrl(userId);
}

export async function removeProfilePhoto(userId) {
  const { error } = await sb.storage.from(BUCKET).remove([`${userId}/avatar`]);
  if (error) throw error;
}

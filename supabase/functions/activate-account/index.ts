// Activación de la cuenta web con el código que la persona sacó en el terminal (válido 24 h).
// Pública por naturaleza: desplegar con verify_jwt = false. Límite de intentos por IP.
import { adminClient, cleanEmail, corsHeaders, reply, sha256 } from "../_shared/util.ts";

const WINDOW_MIN = 15;
const MAX_FAILS_BY_IP = 10;
const BAD_CODE = "Código incorrecto o vencido. Acerca tu tarjeta al terminal del colegio para sacar uno nuevo.";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders(req) });
  if (req.method !== "POST") return reply(req, { error: "method_not_allowed" }, 405);

  const body = await req.json().catch(() => null);
  const email = cleanEmail(body?.email);
  const code = typeof body?.code === "string" ? body.code.slice(0, 24) : "";
  const password = typeof body?.password === "string" ? body.password : "";
  if (!email) return reply(req, { error: "invalid_email", message: "Escribe un correo válido." }, 400);
  if (password.length < 10 || password.length > 128) {
    return reply(req, { error: "weak_password", message: "La contraseña debe tener entre 10 y 128 caracteres." }, 400);
  }
  if (password.toLowerCase() === email) {
    return reply(req, { error: "weak_password", message: "La contraseña no puede ser tu correo." }, 400);
  }

  const ip = req.headers.get("x-forwarded-for")?.split(",")[0].trim() || "unknown";
  const ipHash = await sha256(ip);
  const db = adminClient();
  const since = new Date(Date.now() - WINDOW_MIN * 60_000).toISOString();
  const { count } = await db.from("activation_attempts").select("id", { count: "exact", head: true })
    .eq("ip_hash", ipHash).eq("success", false).gte("created_at", since);
  if ((count ?? 0) >= MAX_FAILS_BY_IP) {
    return reply(req, { error: "too_many_attempts", message: "Demasiados intentos. Espera unos minutos e inténtalo de nuevo." }, 429);
  }

  const { data: profileId } = await db.rpc("activation_lookup", { p_code: code });
  if (!profileId) {
    await db.from("activation_attempts").insert({ ip_hash: ipHash, success: false });
    return reply(req, { error: "invalid_code", message: BAD_CODE }, 400);
  }

  const { error: updErr } = await db.auth.admin.updateUserById(profileId as string, {
    email, password, email_confirm: true,
  });
  if (updErr) {
    const taken = updErr.code === "email_exists" || /already|registered|exists/i.test(updErr.message ?? "");
    if (taken) return reply(req, { error: "email_in_use", message: "Ese correo ya está en uso. Usa otro o inicia sesión." }, 409);
    console.error(updErr);
    return reply(req, { error: "server_error", message: "No se pudo activar. Inténtalo de nuevo." }, 500);
  }

  const { data: done } = await db.rpc("complete_account_activation", { p_profile_id: profileId, p_email: email });
  if (!done) return reply(req, { error: "invalid_code", message: BAD_CODE }, 400);
  await db.from("activation_attempts").insert({ ip_hash: ipHash, success: true });
  return reply(req, { ok: true });
});

// Inicio de sesión con límite de intentos y verificación de cuenta activa.
// Desplegar con: supabase functions deploy auth-login --no-verify-jwt   (es pública por naturaleza)
import { adminClient, anonClient, cleanEmail, corsHeaders, reply, sha256 } from "../_shared/util.ts";

const WINDOW_MIN = 15;     // ventana de conteo
const MAX_BY_EMAIL = 5;    // fallos por correo en la ventana
const MAX_BY_IP = 30;      // fallos por IP en la ventana
const GENERIC = "Correo o contraseña incorrectos.";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders(req) });
  if (req.method !== "POST") return reply(req, { error: "method_not_allowed" }, 405);

  const body = await req.json().catch(() => null);
  const email = cleanEmail(body?.email);
  const password = typeof body?.password === "string" ? body.password : "";
  if (!email || password.length < 1 || password.length > 128) {
    return reply(req, { error: "invalid_credentials", message: GENERIC }, 401);
  }

  const ip = req.headers.get("x-forwarded-for")?.split(",")[0].trim() || "unknown";
  const [emailHash, ipHash] = await Promise.all([sha256(email), sha256(ip)]);
  const db = adminClient();
  const since = new Date(Date.now() - WINDOW_MIN * 60_000).toISOString();

  // Se cuentan también los correos que no existen: el bloqueo es idéntico exista o no la cuenta.
  const [byEmail, byIp] = await Promise.all([
    db.from("login_attempts").select("id", { count: "exact", head: true })
      .eq("email_hash", emailHash).eq("success", false).gte("created_at", since),
    db.from("login_attempts").select("id", { count: "exact", head: true })
      .eq("ip_hash", ipHash).eq("success", false).gte("created_at", since),
  ]);
  if ((byEmail.count ?? 0) >= MAX_BY_EMAIL || (byIp.count ?? 0) >= MAX_BY_IP) {
    return reply(req, { error: "too_many_attempts", message: "Demasiados intentos. Espera unos minutos e inténtalo de nuevo." }, 429);
  }

  const { data, error } = await anonClient().auth.signInWithPassword({ email, password });
  let ok = !error && !!data?.session && !!data?.user;

  if (ok) { // cuenta desactivada = mismo mensaje genérico
    const { data: p } = await db.from("profiles").select("status").eq("id", data!.user!.id).maybeSingle();
    if (p?.status !== "active") ok = false;
  }

  await db.from("login_attempts").insert({ email_hash: emailHash, ip_hash: ipHash, success: ok });
  if (!ok) return reply(req, { error: "invalid_credentials", message: GENERIC }, 401);

  const s = data!.session!;
  return reply(req, {
    session: { access_token: s.access_token, refresh_token: s.refresh_token, expires_at: s.expires_at, token_type: s.token_type },
  });
});

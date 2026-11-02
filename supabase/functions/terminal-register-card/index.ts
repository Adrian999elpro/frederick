// Registro de una persona nueva desde el terminal: tarjeta + nombre (+ rol y curso).
// Solo administradores activos (can_register_cards). Crea una cuenta "pendiente de activar" con
// un correo provisional y una contraseña aleatoria que nadie conoce; la persona la activa después
// con un código (activate-account). Desplegar con verify_jwt = true.
import { adminClient, corsHeaders, HttpError, reply, requireCheck } from "../_shared/util.ts";

const PENDING_DOMAIN = Deno.env.get("PENDING_EMAIL_DOMAIN") ?? "pendiente.frederick.invalid";
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const UID_RE = /^([0-9A-F]{2}){4,10}$/;

function randomPassword(len = 40): string {
  const abc = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789";
  return Array.from(crypto.getRandomValues(new Uint32Array(len)), (n) => abc[n % abc.length]).join("") + "!7";
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders(req) });
  if (req.method !== "POST") return reply(req, { error: "method_not_allowed" }, 405);

  const actor = await requireCheck(req, "can_register_cards");
  if (!actor) return reply(req, { error: "forbidden" }, 403);

  try {
    const body = await req.json().catch(() => null);
    if (!body) throw new HttpError(400, "bad_request");
    const uid = String(body.card_uid ?? "").toUpperCase().replace(/[: -]/g, "");
    const fullName = typeof body.full_name === "string" ? body.full_name.trim().replace(/\s+/g, " ") : "";
    const role = typeof body.role === "string" ? body.role : "estudiante";
    const levelId = body.level_id == null || body.level_id === "" ? null : String(body.level_id);
    if (!UID_RE.test(uid)) throw new HttpError(400, "invalid_card");
    if (fullName.length < 2 || fullName.length > 120) throw new HttpError(400, "invalid_name");
    if (levelId !== null && !UUID_RE.test(levelId)) throw new HttpError(400, "invalid_level");

    const db = adminClient();
    // El PIN: debe haber una sesión de administrador (tarjeta + PIN) abierta en este terminal.
    const { data: session } = await db.rpc("operator_admin_session", { p_operator: actor });
    if (session !== true) return reply(req, { error: "admin_session_required" }, 403);
    if (role === "admin") throw new HttpError(400, "invalid_role");
    const { data: roleRow } = await db.from("roles").select("name").eq("name", role).maybeSingle();
    if (!roleRow) throw new HttpError(400, "invalid_role");
    if (levelId !== null) {
      const { data: lv } = await db.from("school_levels").select("id").eq("id", levelId).maybeSingle();
      if (!lv) throw new HttpError(400, "invalid_level");
    }

    const { data: pre, error: preErr } = await db.rpc("card_registration_precheck", { p_card_uid: uid });
    if (preErr) throw new HttpError(400, "invalid_card");
    if (pre?.taken) return reply(req, { error: "card_already_assigned", owner: pre.owner_name ?? "" }, 409);

    const email = `pendiente-${crypto.randomUUID().replaceAll("-", "").slice(0, 16)}@${PENDING_DOMAIN}`;
    const { data: created, error: createErr } = await db.auth.admin.createUser({
      email, password: randomPassword(), email_confirm: true,
      user_metadata: { full_name: fullName },
      app_metadata: { provisioned: true, role },
    });
    if (createErr || !created.user) throw new HttpError(500, "create_failed");

    const { error: finErr } = await db.rpc("finalize_card_registration", {
      p_actor: actor, p_profile_id: created.user.id, p_card_uid: uid, p_full_name: fullName, p_level_id: levelId,
    });
    if (finErr) {
      await db.auth.admin.deleteUser(created.user.id); // sin cuenta a medias
      if (String(finErr.message).includes("card_already_assigned")) return reply(req, { error: "card_already_assigned", owner: "" }, 409);
      throw new HttpError(500, "register_failed");
    }
    return reply(req, { ok: true, profile_id: created.user.id, name: fullName });
  } catch (e) {
    if (e instanceof HttpError) return reply(req, { error: e.message }, e.status);
    console.error(e);
    return reply(req, { error: "server_error" }, 500);
  }
});

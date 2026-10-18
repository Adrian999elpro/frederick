// Operaciones de administración de usuarios (requieren la clave service_role, por eso viven aquí).
// Cada llamada valida el JWT del llamador y el permiso users.manage EN EL SERVIDOR.
// Acciones: create (por lotes), set_role, set_status, delete.
import { adminClient, cleanEmail, corsHeaders, HttpError, reply, requirePermission } from "../_shared/util.ts";

type Db = ReturnType<typeof adminClient>;
const MAX_BATCH = 100;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function tempPassword(len = 14): string {
  const abc = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789";
  return Array.from(crypto.getRandomValues(new Uint32Array(len)), (n) => abc[n % abc.length]).join("") + "!7";
}
function uuid(v: unknown): string {
  if (typeof v !== "string" || !UUID_RE.test(v)) throw new HttpError(400, "invalid_id");
  return v;
}
const audit = (db: Db, actor: string, action: string, target: string | null, detail: unknown) =>
  db.from("audit_log").insert({ actor, action, target, detail });

async function createUsers(db: Db, actor: string, users: unknown) {
  if (!Array.isArray(users) || users.length === 0 || users.length > MAX_BATCH) throw new HttpError(400, "invalid_batch");
  const { data: roles } = await db.from("roles").select("name");
  const valid = new Set((roles ?? []).map((r: { name: string }) => r.name));
  const results: Record<string, unknown>[] = [];

  for (const u of users as Record<string, unknown>[]) {
    const email = cleanEmail(u?.email);
    const role = typeof u?.role === "string" ? u.role : "";
    const fullName = typeof u?.full_name === "string" ? u.full_name.trim().slice(0, 120) : "";
    if (!email || !valid.has(role)) { results.push({ email: u?.email ?? null, ok: false, error: "invalid_data" }); continue; }

    const given = typeof u?.password === "string" && u.password.length >= 10 ? u.password : null;
    const password = given ?? tempPassword();
    const { data, error } = await db.auth.admin.createUser({
      email, password, email_confirm: true,
      user_metadata: { full_name: fullName },
      app_metadata: { provisioned: true, role },   // el trigger de la BD usa estos valores
    });
    if (error || !data.user) { results.push({ email, ok: false, error: "create_failed" }); continue; }
    await db.from("profiles").update({ must_change_password: true }).eq("id", data.user.id);
    results.push({ email, ok: true, temp_password: given ? undefined : password });
  }
  await audit(db, actor, "users.create", null, { requested: users.length, created: results.filter((r) => r.ok).length });
  return { results };
}

async function setRole(db: Db, actor: string, b: Record<string, unknown>) {
  const id = uuid(b.user_id);
  if (id === actor) throw new HttpError(400, "cannot_change_self");
  const { data: role } = await db.from("roles").select("id").eq("name", String(b.role ?? "")).maybeSingle();
  if (!role) throw new HttpError(400, "invalid_role");
  const { data, error } = await db.from("profiles").update({ role_id: role.id }).eq("id", id).select("id");
  if (error) throw error;
  if (!data?.length) throw new HttpError(404, "not_found");
  await audit(db, actor, "users.set_role", id, { role: b.role });
  return { ok: true };
}

async function setStatus(db: Db, actor: string, b: Record<string, unknown>) {
  const id = uuid(b.user_id);
  if (id === actor) throw new HttpError(400, "cannot_change_self");
  if (b.status !== "active" && b.status !== "disabled") throw new HttpError(400, "invalid_status");
  const { data, error } = await db.from("profiles").update({ status: b.status }).eq("id", id).select("id");
  if (error) throw error;
  if (!data?.length) throw new HttpError(404, "not_found");
  // Además de la bandera en la BD (efecto inmediato vía RLS), se bloquea el renovar sesión en Auth.
  await db.auth.admin.updateUserById(id, { ban_duration: b.status === "disabled" ? "876000h" : "none" });
  await audit(db, actor, "users.set_status", id, { status: b.status });
  return { ok: true };
}

async function deleteUser(db: Db, actor: string, b: Record<string, unknown>) {
  const id = uuid(b.user_id);
  if (id === actor) throw new HttpError(400, "cannot_change_self");
  const { error } = await db.auth.admin.deleteUser(id);
  if (error) throw new HttpError(404, "not_found");
  await audit(db, actor, "users.delete", id, null);
  return { ok: true };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders(req) });
  if (req.method !== "POST") return reply(req, { error: "method_not_allowed" }, 405);

  const actor = await requirePermission(req, "users.manage");
  if (!actor) return reply(req, { error: "forbidden" }, 403);

  const body = await req.json().catch(() => null);
  if (!body || typeof body.action !== "string") return reply(req, { error: "bad_request" }, 400);

  const db = adminClient();
  try {
    switch (body.action) {
      case "create": return reply(req, await createUsers(db, actor, body.users));
      case "set_role": return reply(req, await setRole(db, actor, body));
      case "set_status": return reply(req, await setStatus(db, actor, body));
      case "delete": return reply(req, await deleteUser(db, actor, body));
      default: return reply(req, { error: "unknown_action" }, 400);
    }
  } catch (e) {
    if (e instanceof HttpError) return reply(req, { error: e.message }, e.status);
    console.error(e);
    return reply(req, { error: "server_error" }, 500);
  }
});

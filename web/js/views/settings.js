import { sb, esc, toast, showError, withBusy, $ } from "../core.js";

const DOMAIN_RE = /^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$/;

export async function render(root) {
  const [s, r, rp] = await Promise.all([
    sb.from("app_settings").select("value").eq("key", "registration").single(),
    sb.from("roles").select("id,name").order("name"),
    sb.from("role_permissions").select("role_id,permission_code"),
  ]);
  const err = s.error || r.error || rp.error; if (err) return showError(err);
  const cfg = s.data.value;
  // Solo se ofrecen roles sin permisos de administración (el servidor también lo exige).
  const privileged = new Set(rp.data.filter((x) => x.permission_code.endsWith(".manage")).map((x) => x.role_id));
  const roles = r.data.filter((x) => !privileged.has(x.id));
  const modes = [
    ["closed", "Cerrado", "Solo el administrador crea cuentas."],
    ["open", "Abierto", "Cualquier persona puede registrarse con confirmación por correo."],
    ["domain", "Por dominio", "Solo correos de los dominios indicados."],
  ];

  root.innerHTML = `<h2>Registro y ajustes</h2>
  <form id="f" class="card form">
    <h3>Registro de usuarios</h3>
    ${modes.map(([v, t, d]) => `<label class="row"><input type="radio" name="mode" value="${v}" ${cfg.mode === v ? "checked" : ""}>
      <span><strong>${t}</strong><br><span class="hint">${d}</span></span></label>`).join("")}
    <label>Dominios permitidos (uno por línea)
      <textarea name="domains" placeholder="escuela.edu.ec">${esc((cfg.allowed_domains ?? []).join("\n"))}</textarea></label>
    <label>Rol que recibe quien se registra
      <select name="role">${roles.map((x) => `<option ${x.name === cfg.default_role ? "selected" : ""}>${esc(x.name)}</option>`).join("")}</select></label>
    <p class="hint">Las cuentas auto-registradas confirman su correo antes de poder entrar.</p>
    <div><button class="btn primary" type="submit">Guardar</button></div>
  </form>`;

  $("#f", root).addEventListener("submit", async (e) => {
    e.preventDefault(); const f = e.currentTarget;
    const domains = f.domains.value.split(/[\s,]+/).map((d) => d.trim().toLowerCase()).filter(Boolean);
    if (domains.some((d) => !DOMAIN_RE.test(d))) return toast("Revisa los dominios: use el formato escuela.edu.ec", "err");
    if (f.mode.value === "domain" && !domains.length) return toast("Indica al menos un dominio.", "err");
    await withBusy($("[type=submit]", f), async () => {
      const { error } = await sb.from("app_settings").update({
        value: { mode: f.mode.value, allowed_domains: domains, default_role: f.role.value },
      }).eq("key", "registration");
      if (error) return showError(error); toast("Ajustes guardados.");
    });
  });
}

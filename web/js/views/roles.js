import { sb, esc, toast, showError, confirmBox, invalidate, $, $$ } from "../core.js";

export async function render(root) {
  const [r, p, rp] = await Promise.all([
    sb.from("roles").select("id,name,description,is_system").order("name"),
    sb.from("permissions").select("code,description").order("code"),
    sb.from("role_permissions").select("role_id,permission_code"),
  ]);
  const err = r.error || p.error || rp.error; if (err) return showError(err);
  const roles = r.data, perms = p.data;
  const key = (rid, code) => `${rid}|${code}`;
  const original = new Set(rp.data.map((x) => key(x.role_id, x.permission_code)));

  root.innerHTML = `<h2>Roles y permisos</h2>
  <form id="f-role" class="card form">
    <h3>Nuevo rol</h3>
    <div class="row">
      <label>Nombre<input name="name" required pattern="[a-z][a-z0-9_]{1,30}" maxlength="31" placeholder="supervisor"></label>
      <label>Descripción<input name="description" maxlength="200"></label>
    </div>
    <p class="hint">Nombre en minúsculas, sin espacios (letras, números y guion bajo).</p>
    <div><button class="btn primary" type="submit">Crear rol</button></div>
  </form>
  <div class="card" id="matrix">
    <div class="table-wrap"><table class="table">
      <thead><tr><th>Permiso</th>${roles.map((x) => `<th class="center">${esc(x.name)}${x.is_system ? "" : ` <button class="btn danger sm" data-del="${esc(x.id)}" aria-label="Eliminar rol ${esc(x.name)}">✕</button>`}</th>`).join("")}</tr></thead>
      <tbody>${perms.map((pm) => `<tr><td><strong>${esc(pm.code)}</strong><br><span class="hint">${esc(pm.description)}</span></td>
        ${roles.map((x) => `<td class="center"><input type="checkbox" data-role="${esc(x.id)}" data-code="${esc(pm.code)}"
           aria-label="${esc(x.name)}: ${esc(pm.code)}" ${original.has(key(x.id, pm.code)) ? "checked" : ""} ${x.name === "admin" ? "disabled" : ""}></td>`).join("")}</tr>`).join("")}</tbody>
    </table></div>
    <p class="hint">El rol admin siempre conserva todos los permisos. Los cambios se guardan por rol en una sola operación.</p>
    <button id="save" class="btn primary" type="button">Guardar cambios</button>
  </div>`;

  $("#save", root).addEventListener("click", async () => {
    const changed = roles.filter((x) => x.name !== "admin").map((x) => {
      const codes = $$(`input[data-role="${x.id}"]:checked`, root).map((c) => c.dataset.code);
      const was = perms.filter((pm) => original.has(key(x.id, pm.code))).map((pm) => pm.code);
      return { id: x.id, codes, dirty: codes.length !== was.length || codes.some((c) => !was.includes(c)) };
    }).filter((x) => x.dirty);
    if (!changed.length) return toast("No hay cambios por guardar.");
    const res = await Promise.all(changed.map((x) => sb.rpc("set_role_permissions", { p_role: x.id, p_codes: x.codes })));
    const bad = res.find((x) => x.error); if (bad) return showError(bad.error);
    toast("Permisos guardados."); render(root);
  });

  $("#f-role", root).addEventListener("submit", async (e) => {
    e.preventDefault(); const f = e.currentTarget;
    const { error } = await sb.from("roles").insert({ name: f.name.value.trim(), description: f.description.value.trim() });
    if (error) return showError(error, error.code === "23505" ? "Ya existe un rol con ese nombre." : undefined);
    invalidate("roles"); toast("Rol creado."); render(root);
  });

  $("#matrix", root).addEventListener("click", async (e) => {
    const b = e.target.closest("[data-del]"); if (!b) return;
    if (!await confirmBox("Se eliminará el rol. ¿Continuar?", "Eliminar")) return;
    const { error } = await sb.from("roles").delete().eq("id", b.dataset.del);
    if (error) return showError(error, error.code === "23503" ? "El rol tiene usuarios asignados." : undefined);
    invalidate("roles"); toast("Rol eliminado."); render(root);
  });
}

import { sb, esc, toast, showError, confirmBox, invoke, can, cached, $, withBusy } from "../core.js";

const PAGE = 50;
const csvCell = (v) => { let s = String(v ?? ""); if (/^[=+\-@\t\r]/.test(s)) s = "'" + s; return `"${s.replace(/"/g, '""')}"`; };

export async function render(root, access) {
  const manage = can(access, "users.manage");
  const roles = await cached("roles", 60_000, async () => (await sb.from("roles").select("id,name").order("name")).data ?? []);
  let page = 0, q = "", timer;

  root.innerHTML = `<h2>Usuarios</h2>
  ${manage ? `<form id="f-create" class="card form">
    <h3>Crear usuarios</h3>
    <p class="hint">Una línea por persona: <code>correo, nombre completo, rol</code>. Hasta 100 por vez. Cada cuenta recibe una contraseña temporal que deberá cambiar al ingresar. Roles: ${roles.map((r) => esc(r.name)).join(", ")}.</p>
    <textarea name="lines" required placeholder="ana@correo.com, Ana Pérez, estudiante"></textarea>
    <div><button class="btn primary" type="submit">Crear usuarios</button></div>
    <div id="created"></div>
  </form>` : ""}
  <div class="card">
    <input id="q" type="search" placeholder="Buscar por nombre o correo" aria-label="Buscar usuarios" maxlength="60">
    <div class="table-wrap"><table class="table">
      <thead><tr><th>Nombre</th><th>Correo</th><th>Rol</th><th>Estado</th>${manage ? "<th></th>" : ""}</tr></thead>
      <tbody id="rows"></tbody></table></div>
    <button id="more" class="btn ghost" type="button" hidden>Cargar más</button>
  </div>`;
  const rows = $("#rows", root);

  const rowHTML = (u) => `<tr data-id="${esc(u.id)}">
    <td>${esc(u.full_name || "—")}</td><td>${esc(u.email)}</td>
    <td>${manage && u.id !== access.id
      ? `<select data-act="role" aria-label="Rol de ${esc(u.email)}">${roles.map((r) => `<option ${r.name === u.role?.name ? "selected" : ""}>${esc(r.name)}</option>`).join("")}</select>`
      : esc(u.role?.name ?? "")}</td>
    <td><span class="badge ${u.status === "active" ? "ok" : "off"}">${u.status === "active" ? "Activo" : "Desactivado"}</span></td>
    ${manage ? `<td class="actions">${u.id === access.id ? "" :
      `<button class="btn ghost sm" data-act="toggle" data-status="${esc(u.status)}">${u.status === "active" ? "Desactivar" : "Activar"}</button>
       <button class="btn danger sm" data-act="delete">Eliminar</button>`}</td>` : ""}</tr>`;

  async function load(reset) {
    if (reset) { page = 0; rows.innerHTML = ""; }
    let query = sb.from("profiles").select("id,email,full_name,status,role:roles(name)")
      .order("full_name").order("id").range(page * PAGE, page * PAGE + PAGE);     // PAGE+1 filas: así se sabe si hay más
    const s = q.replace(/[%,()*\\_"']/g, " ").trim();
    if (s) query = query.or(`email.ilike.%${s}%,full_name.ilike.%${s}%`);
    const { data, error } = await query;
    if (error) return showError(error);
    rows.insertAdjacentHTML("beforeend", data.slice(0, PAGE).map(rowHTML).join(""));
    if (reset && !data.length) rows.innerHTML = `<tr><td colspan="5" class="muted">No hay usuarios que coincidan.</td></tr>`;
    $("#more", root).hidden = data.length <= PAGE; page++;
  }

  $("#q", root).addEventListener("input", (e) => { clearTimeout(timer); timer = setTimeout(() => { q = e.target.value; load(true); }, 300); });
  $("#more", root).addEventListener("click", () => load(false));

  rows.addEventListener("change", async (e) => {
    if (e.target.dataset.act !== "role") return;
    try { await invoke("admin-users", { action: "set_role", user_id: e.target.closest("tr").dataset.id, role: e.target.value }); toast("Rol actualizado."); }
    catch (err) { showError(err); load(true); }
  });
  rows.addEventListener("click", async (e) => {
    const b = e.target.closest("button[data-act]"); if (!b) return;
    const id = b.closest("tr").dataset.id;
    try {
      if (b.dataset.act === "toggle") {
        const next = b.dataset.status === "active" ? "disabled" : "active";
        if (next === "disabled" && !await confirmBox("La persona perderá el acceso de inmediato. ¿Desactivar la cuenta?", "Desactivar")) return;
        await invoke("admin-users", { action: "set_status", user_id: id, status: next }); toast("Estado actualizado.");
      } else if (b.dataset.act === "delete") {
        if (!await confirmBox("Se eliminará la cuenta de forma permanente. ¿Continuar?", "Eliminar")) return;
        await invoke("admin-users", { action: "delete", user_id: id }); toast("Cuenta eliminada.");
      }
      load(true);
    } catch (err) { showError(err); }
  });

  if (manage) $("#f-create", root).addEventListener("submit", async (e) => {
    e.preventDefault(); const f = e.currentTarget;
    const users = f.lines.value.split("\n").map((l) => l.trim()).filter(Boolean).map((l) => {
      const [email, full_name, role] = l.split(",").map((p) => p.trim()); return { email, full_name, role };
    });
    await withBusy($("[type=submit]", f), async () => {
      try {
        const { results } = await invoke("admin-users", { action: "create", users });
        const ok = results.filter((r) => r.ok);
        $("#created", f).innerHTML = `<p class="callout ${ok.length ? "" : "err"}">${ok.length} de ${results.length} cuentas creadas. Guarda las contraseñas temporales: no se volverán a mostrar.</p>
          <div class="table-wrap"><table class="table"><thead><tr><th>Correo</th><th>Resultado</th><th>Contraseña temporal</th></tr></thead><tbody>
          ${results.map((r) => `<tr><td>${esc(r.email)}</td><td>${r.ok ? "Creada" : "No se pudo crear (" + esc(r.error) + ")"}</td><td><code>${esc(r.temp_password ?? "")}</code></td></tr>`).join("")}
          </tbody></table></div><button type="button" class="btn ghost" id="dl">Descargar CSV</button>`;
        $("#dl", f).addEventListener("click", () => {
          const csv = "correo,resultado,contrasena_temporal\r\n" + results.map((r) => [r.email, r.ok ? "creada" : r.error, r.temp_password ?? ""].map(csvCell).join(",")).join("\r\n");
          const a = document.createElement("a"); a.href = URL.createObjectURL(new Blob(["\ufeff" + csv], { type: "text/csv;charset=utf-8" }));
          a.download = "usuarios-creados.csv"; a.click(); URL.revokeObjectURL(a.href);
        });
        if (ok.length) { f.lines.value = ""; load(true); }
      } catch (err) { showError(err); }
    });
  });

  load(true);
}

import { sb, esc, toast, showError, confirmBox, invoke, can, cached, $, withBusy } from "../core.js?v=20261018-community";

import { roleLabel } from "../person-card.js?v=20261018-community";
const PAGE = 50;
const csvCell = (v) => { let s = String(v ?? ""); if (/^[=+\-@\t\r]/.test(s)) s = "'" + s; return `"${s.replace(/"/g, '""')}"`; };

export async function render(root, access) {
  const manage = can(access, "users.manage");
  const roles = await cached("roles", 60_000, async () => (await sb.from("roles").select("id,name").order("name")).data ?? []);
  let page = 0, q = "", timer;

  root.innerHTML = `<h2>Usuarios</h2>
  <section class="card"><h3>Registro de estudiantes</h3><p>Cada estudiante puede crear su cuenta con su correo, confirmar el mensaje recibido y completar sus datos en <strong>Mi tarjeta y curso</strong>.</p><a class="btn ghost" href="index.html?view=register" target="_blank" rel="noopener">Abrir registro</a></section>
  ${manage?'<section class="card"><h3>Solicitudes de curso y tarjeta</h3><div id="enrollment-requests">Cargando solicitudes…</div></section>':""}
  ${manage ? `<form id="f-create" class="card form">
    <h3>Creación masiva · solo administradores</h3>
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
      ? `<select data-act="role" aria-label="Rol de ${esc(u.email)}">${roles.map((r) => `<option value="${esc(r.name)}" ${r.name === u.role?.name ? "selected" : ""}>${esc(roleLabel(r.name))}</option>`).join("")}</select>`
      : esc(roleLabel(u.role?.name))}</td>
    <td><span class="badge ${u.status === "active" ? "ok" : "off"}">${u.status === "active" ? "Activo" : "Desactivado"}</span></td>
    ${manage ? `<td class="actions"><button class="btn ghost sm" data-act="privacy">Privacidad</button>${u.id === access.id ? "" :
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
      if (b.dataset.act === "privacy") {
        const current=await sb.from("profile_customizations").select("visibility,show_grades").eq("profile_id",id).maybeSingle();
        if(current.error)throw current.error;
        const dialog=document.createElement("dialog");dialog.className="dlg";
        dialog.innerHTML=`<form class="form"><h2>Privacidad del usuario</h2><label>Visibilidad<select name="visibility"><option value="private">Privado</option><option value="public">Público en el colegio</option></select></label><label class="row"><input name="grades" type="checkbox"> Compartir calificaciones si el perfil es público</label><p class="hint">No se comparten correo, teléfono ni datos del representante.</p><p role="status"></p><div class="row"><button type="button" class="btn ghost" id="cancel">Cancelar</button><button class="btn primary" type="submit">Guardar</button></div></form>`;
        document.body.append(dialog);const form=$("form",dialog);form.visibility.value=current.data?.visibility||"private";form.grades.checked=current.data?.show_grades===true;
        $("#cancel",dialog).onclick=()=>dialog.close();dialog.addEventListener("close",()=>dialog.remove());
        form.onsubmit=async e=>{e.preventDefault();await withBusy($("button[type=submit]",form),async()=>{const {error}=await sb.rpc("set_student_privacy",{p_profile_id:id,p_visibility:form.visibility.value,p_show_grades:form.grades.checked});if(error){$("[role=status]",form).textContent="No se pudo guardar la privacidad.";return;}toast("Privacidad actualizada.");dialog.close();});};dialog.showModal();return;
      } else if (b.dataset.act === "toggle") {
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
  if(manage)loadRequests();
  async function loadRequests(){
    const box=$("#enrollment-requests",root);
    const {data,error}=await sb.from("enrollment_requests").select("profile_id,card_uid,level_id,profiles(full_name,email),school_levels(name)").eq("status","pending").order("updated_at").limit(50);
    if(error){box.textContent="No se pudieron cargar las solicitudes.";return;}
    box.innerHTML=data.length?data.map(r=>`<article class="card" data-request="${r.profile_id}"><strong>${esc(r.profiles?.full_name)}</strong><p>${esc(r.profiles?.email)} · ${esc(r.school_levels?.name||"Sin curso")}</p><p>Tarjeta: ${esc(r.card_uid||"Sin tarjeta")}</p><div class="row"><button class="btn primary" data-review="yes">Aprobar</button><button class="btn ghost" data-review="no">Rechazar</button></div></article>`).join(""):'<p class="muted">No hay solicitudes pendientes.</p>';
    box.onclick=async e=>{const button=e.target.closest("[data-review]");if(!button)return;await withBusy(button,async()=>{const {error}=await sb.rpc("review_enrollment",{p_profile_id:button.closest("[data-request]").dataset.request,p_approve:button.dataset.review==="yes"});if(error){showError(error,error.message?.includes("card_already_assigned")?"Esta tarjeta ya pertenece a otra cuenta.":"No se pudo revisar la solicitud.");return;}toast("Solicitud revisada.");loadRequests();});};
  }
}


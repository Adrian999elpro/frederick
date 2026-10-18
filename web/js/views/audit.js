import { sb, esc, fmtDate, showError, $ } from "../core.js";

const PAGE = 50;

export async function render(root) {
  root.innerHTML = `<h2>Auditoría</h2><div class="card">
    <div class="table-wrap"><table class="table"><thead><tr><th>Fecha</th><th>Quién</th><th>Acción</th><th>Objetivo</th><th>Detalle</th></tr></thead>
    <tbody id="rows"></tbody></table></div><button id="more" class="btn ghost" type="button" hidden>Cargar más</button></div>`;
  let page = 0;
  async function load() {
    const { data, error } = await sb.from("audit_log").select("id,action,target,detail,created_at,actor:profiles(email)")
      .order("created_at", { ascending: false }).order("id", { ascending: false }).range(page * PAGE, page * PAGE + PAGE);
    if (error) return showError(error);
    $("#rows", root).insertAdjacentHTML("beforeend", data.slice(0, PAGE).map((a) => `<tr><td>${esc(fmtDate(a.created_at))}</td>
      <td>${esc(a.actor?.email ?? "—")}</td><td>${esc(a.action)}</td><td>${esc(a.target ?? "")}</td>
      <td><code>${esc(a.detail ? JSON.stringify(a.detail).slice(0, 120) : "")}</code></td></tr>`).join(""));
    $("#more", root).hidden = data.length <= PAGE; page++;
  }
  $("#more", root).addEventListener("click", load); load();
}

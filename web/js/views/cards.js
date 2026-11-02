// Vista: Tarjetas NFC (solo lectura). La web no lee NFC: las tarjetas se registran, asignan o
// reemplazan únicamente en la app del terminal y solo por administradores. Aquí se consulta
// quién tiene tarjeta y los administradores pueden bloquear o desbloquear una tarjeta perdida.
import { sb, $, esc, toast, confirmBox, withBusy, showError } from "../core.js?v=20261018-community";

const FILTERS = [
  ["all", "Todos"], ["with", "Con tarjeta"], ["without", "Sin tarjeta"],
  ["pending", "Pendientes de activar"], ["blocked", "Bloqueadas"],
];
const norm = (s) => String(s ?? "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();

export async function render(root, access) {
  const isAdmin = access.role === "admin" && access.permissions.includes("cards.register");
  root.innerHTML = `
    <h1>Tarjetas NFC</h1>
    <p class="muted">Todas las personas registradas y su tarjeta. Las tarjetas se registran en la <strong>app del terminal</strong> (solo administradores); desde aquí no se lee NFC.</p>
    <div class="card" id="cards-box">
      <div class="row" style="gap:.75rem;flex-wrap:wrap;margin-bottom:1rem;align-items:center">
        <input type="search" id="search-card" placeholder="Buscar por nombre o correo…" style="max-width:320px;flex:1;min-width:200px">
        <select id="filter-card" aria-label="Filtrar" style="width:auto;min-width:200px">${FILTERS.map(([v, l]) => `<option value="${v}">${l}</option>`).join("")}</select>
        <span class="hint muted" id="card-count" role="status"></span>
      </div>
      <div class="table-wrap"><table class="table">
        <thead><tr><th>Persona</th><th>Correo</th><th>Tarjeta</th><th>Estado</th><th>Registrada</th>${isAdmin ? '<th class="actions"></th>' : ""}</tr></thead>
        <tbody id="cards-tbody"><tr><td colspan="6" class="center muted">Cargando…</td></tr></tbody>
      </table></div>
    </div>`;

  let rows = [];
  async function load() {
    const { data, error } = await sb.rpc("list_card_directory");
    if (error) { $("#cards-tbody", root).innerHTML = `<tr><td colspan="6" class="center muted">No se pudo cargar la lista.</td></tr>`; return showError(error); }
    rows = data ?? [];
    draw();
  }

  function state(r) {
    if (r.status === "disabled") return '<span class="badge gray">Cuenta desactivada</span>';
    if (!r.card_id) return '<span class="badge warn">Sin tarjeta</span>';
    if (!r.card_active) return '<span class="badge off">Bloqueada</span>';
    if (r.activation_pending) return `<span class="badge blue">${r.code_valid ? "Código entregado" : "Pendiente de activar"}</span>`;
    return '<span class="badge ok">Activa</span>';
  }

  function draw() {
    const q = norm($("#search-card", root).value), f = $("#filter-card", root).value;
    const list = rows.filter((r) => {
      if (q && !norm(`${r.full_name} ${r.email ?? ""}`).includes(q)) return false;
      if (f === "with") return r.card_id && r.card_active;
      if (f === "without") return !r.card_id;
      if (f === "pending") return r.activation_pending;
      if (f === "blocked") return r.card_id && !r.card_active;
      return true;
    });
    const withCard = rows.filter((r) => r.card_id && r.card_active).length;
    $("#card-count", root).textContent = `${list.length} de ${rows.length} personas · ${withCard} con tarjeta activa`;
    $("#cards-tbody", root).innerHTML = list.length ? list.map((r) => `
      <tr>
        <td><strong>${esc(r.full_name || "—")}</strong><div class="hint muted">${esc([r.role, r.level].filter(Boolean).join(" · "))}</div></td>
        <td>${r.email ? esc(r.email) : '<span class="muted">Aún sin correo</span>'}</td>
        <td>${r.card_id ? `<code>${esc(r.card_hint)}</code>` : "—"}</td>
        <td>${state(r)}</td>
        <td>${r.card_since ? esc(new Date(r.card_since).toLocaleDateString("es-EC", { day: "numeric", month: "short", year: "numeric" })) : "—"}${r.registered_by_name ? `<div class="hint muted">por ${esc(r.registered_by_name)}</div>` : ""}</td>
        ${isAdmin ? `<td class="actions">${r.card_id ? `<button class="btn ghost sm" data-card="${r.card_id}" data-active="${r.card_active ? "0" : "1"}">${r.card_active ? "Bloquear" : "Desbloquear"}</button>` : ""}</td>` : ""}
      </tr>`).join("") : `<tr><td colspan="6" class="center muted">No hay personas que coincidan.</td></tr>`;
  }

  $("#search-card", root).addEventListener("input", draw);
  $("#filter-card", root).addEventListener("change", draw);
  $("#cards-tbody", root).addEventListener("click", async (e) => {
    const b = e.target.closest("[data-card]");
    if (!b) return;
    const active = b.dataset.active === "1";
    if (!await confirmBox(active ? "¿Desbloquear esta tarjeta?" : "¿Bloquear esta tarjeta? Dejará de funcionar en el terminal hasta que la desbloquees.", active ? "Desbloquear" : "Bloquear")) return;
    await withBusy(b, async () => {
      const { error } = await sb.rpc("set_card_active", { p_card_id: b.dataset.card, p_active: active });
      if (error) return showError(error);
      toast(active ? "Tarjeta desbloqueada." : "Tarjeta bloqueada.");
      await load();
    });
  });
  await load();
}

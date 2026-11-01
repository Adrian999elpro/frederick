import { sb, esc, fmtDate, showError, $ } from "../core.js?v=20261018-community";

const EVENT_NAMES = {
  admin_card: "Tarjeta administrativa leída",
  mode_changed: "Modo del terminal cambiado",
  poll_pinned: "Votación fijada",
  poll_created: "Votación creada",
  poll_status: "Estado de votación cambiado",
  applications_toggled: "Postulaciones abiertas o cerradas",
  unlock: "Teléfono desbloqueado",
};

export async function render(root) {
  root.innerHTML = `<h2>Actividad del terminal</h2>
    <p class="muted">Registro de aperturas, cambios y desbloqueos del teléfono escolar.</p>
    <section class="card">
      <div class="table-wrap"><table class="table">
        <thead><tr><th>Fecha</th><th>Cuenta del teléfono</th><th>Administrador</th><th>Actividad</th><th>Detalle</th></tr></thead>
        <tbody id="terminal-event-rows"><tr><td colspan="5" class="muted">Cargando actividad…</td></tr></tbody>
      </table></div>
    </section>`;

  const { data, error } = await sb.rpc("list_terminal_events", { p_limit: 500 });
  if (error) return showError(error);

  const rows = data ?? [];
  const body = $("#terminal-event-rows", root);
  if (!rows.length) {
    body.innerHTML = `<tr><td colspan="5" class="muted">Aún no hay actividad registrada.</td></tr>`;
    return;
  }

  body.innerHTML = rows.map((row) => {
    const operator = [row.operator_name, row.operator_email].filter(Boolean).join(" · ");
    const detail = row.detail && typeof row.detail === "object" && Object.keys(row.detail).length
      ? JSON.stringify(row.detail) : "—";
    return `<tr>
      <td>${esc(fmtDate(row.created_at))}</td>
      <td>${esc(operator || "—")}</td>
      <td>${esc(row.actor_name || "—")}</td>
      <td>${esc(EVENT_NAMES[row.event] || row.event || "—")}</td>
      <td><code>${esc(detail)}</code></td>
    </tr>`;
  }).join("");
}

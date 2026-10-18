// Estadísticas Electorales: participación y resultados por lista, con foto del presidente.
import { sb, esc, photoUrls, initials, showError, $, $$ } from "../core.js";

const pct = (n, d) => (d ? (n * 100) / d : 0);
const fmt = (x) => `${x.toFixed(1).replace(".", ",")} %`;

export async function render(root) {
  const { data: elections, error } = await sb.from("elections").select("id,title,status").order("created_at", { ascending: false });
  if (error) return showError(error);
  root.innerHTML = `<h2>Estadísticas Electorales</h2>` + (elections.length
    ? `<div class="card row"><label>Votación<select id="sel">${elections.map((e) => `<option value="${esc(e.id)}">${esc(e.title)}</option>`).join("")}</select></label>
       <button id="refresh" class="btn ghost" type="button">Actualizar</button></div><div id="out"></div>`
    : `<p class="card muted">Aún no hay votaciones.</p>`);
  if (!elections.length) return;

  const out = $("#out", root);
  async function load() {
    const { data, error: err } = await sb.rpc("election_results", { p_election: $("#sel", root).value });   // una sola llamada
    if (err) {
      if (String(err.message).includes("results_hidden")) out.innerHTML = `<p class="callout warn">Los resultados se publican cuando la votación se cierre.</p>`;
      else { out.innerHTML = ""; showError(err); }
      return;
    }
    const urls = await photoUrls(data.lists.map((l) => l.president_photo));
    const total = data.total_votes, top = Math.max(0, ...data.lists.map((l) => l.votes)), closed = data.status === "closed";
    out.innerHTML = `${closed ? "" : `<p class="callout warn">Resultados parciales: la votación sigue abierta.</p>`}
      <div class="stats">
        <div class="stat"><b>${total}</b><span>votos emitidos</span></div>
        <div class="stat"><b>${fmt(pct(total, data.eligible))}</b><span>participación (${total} de ${data.eligible})</span></div>
        <div class="stat"><b>${data.blank}</b><span>votos en blanco</span></div>
      </div>
      <div class="card bars">${data.lists.map((l) => `<div class="bar-row ${closed && top > 0 && l.votes === top ? "lead" : ""}">
        ${urls[l.president_photo] ? `<img class="photo sm" src="${esc(urls[l.president_photo])}" alt="Foto de ${esc(l.president_name)}">` : `<span class="photo sm" aria-hidden="true">${esc(initials(l.president_name))}</span>`}
        <div><div class="bar-head"><span><strong>Lista ${Number(l.number)} · ${esc(l.name)}</strong> — ${esc(l.president_name)}</span>
          <span>${l.votes} votos · ${fmt(pct(l.votes, total))}</span></div>
          <div class="bar"><i data-w="${pct(l.votes, total).toFixed(2)}"></i></div></div></div>`).join("") || `<p class="muted">Esta votación no tiene listas.</p>`}</div>`;
    $$("[data-w]", out).forEach((i) => requestAnimationFrame(() => { i.style.width = `${i.dataset.w}%`; }));
  }
  $("#sel", root).addEventListener("change", load);
  $("#refresh", root).addEventListener("click", load);
  load();
}

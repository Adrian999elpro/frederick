// Papeleta de votación: una lista por tarjeta con foto del presidente, voto en blanco y confirmación.
import { sb, esc, fmtDate, photoUrls, initials, toast, showError, confirmBox, withBusy, $ } from "../core.js?v=20261018-community";

const photo = (l, urls) => urls[l.president_photo]
  ? `<img class="photo" src="${esc(urls[l.president_photo])}" alt="Foto de ${esc(l.president_name)}">`
  : `<span class="photo" aria-hidden="true">${esc(initials(l.president_name))}</span>`;

const doneHTML = (title) => `<section class="ballot"><header><h3>${esc(title)}</h3></header>
  <p>Tu voto quedó registrado. Gracias por participar.</p></section>`;

const ballotHTML = (e, ls, urls) => `<section class="ballot" data-eid="${esc(e.id)}">
  <header><h3>${esc(e.title)}</h3><p class="muted">Cierra el ${esc(fmtDate(e.ends_at))}. Tu voto es secreto y no se puede cambiar.</p></header>
  <fieldset><legend class="sr-only">Elige una opción</legend>
    ${ls.map((l) => `<label class="ballot-row"><input type="radio" name="o-${esc(e.id)}" value="${esc(l.id)}">
      <span class="num">${Number(l.number)}</span>${photo(l, urls)}
      <span class="who"><strong>${esc(l.name)}</strong><span>Presidente/a: ${esc(l.president_name)}</span>${l.slogan ? `<em>${esc(l.slogan)}</em>` : ""}</span>
      <span class="mark" aria-hidden="true"></span></label>`).join("")}
    <label class="ballot-row blank"><input type="radio" name="o-${esc(e.id)}" value="">
      <span class="num">—</span><span class="who"><strong>Voto en blanco</strong></span><span class="mark" aria-hidden="true"></span></label>
  </fieldset>
  <button class="btn primary" type="button" data-vote disabled>Emitir voto</button></section>`;

export async function render(root) {
  root.innerHTML = `<h2>Votar</h2><div id="box"></div>`;
  const box = $("#box", root);
  const now = new Date().toISOString();
  const { data: elections, error } = await sb.from("elections")
    .select("id,title,ends_at,my_receipt:vote_receipts(voted_at)")      // una sola consulta: votaciones + si ya votó
    .eq("status", "open").lte("starts_at", now).gt("ends_at", now).order("ends_at");
  if (error) return showError(error);
  if (!elections.length) { box.innerHTML = `<p class="card muted">No hay votaciones abiertas por ahora.</p>`; return; }

  const pending = elections.filter((e) => !e.my_receipt?.length);
  let lists = [];
  if (pending.length) {
    const r = await sb.from("election_lists").select("id,election_id,number,name,slogan,president_name,president_photo")
      .in("election_id", pending.map((e) => e.id)).order("number");
    if (r.error) return showError(r.error); lists = r.data;
  }
  const urls = await photoUrls(lists.map((l) => l.president_photo));
  box.innerHTML = elections.map((e) => e.my_receipt?.length ? doneHTML(e.title) : ballotHTML(e, lists.filter((l) => l.election_id === e.id), urls)).join("");

  box.addEventListener("change", (ev) => {
    const s = ev.target.closest(".ballot"); if (s && ev.target.type === "radio") $("[data-vote]", s).disabled = false;
  });
  box.addEventListener("click", async (ev) => {
    const b = ev.target.closest("[data-vote]"); if (!b) return;
    const s = b.closest(".ballot"), sel = $("input:checked", s); if (!sel) return;
    const label = sel.value ? $("strong", sel.closest("label")).textContent : "voto en blanco";
    if (!await confirmBox(`Vas a votar por: ${label}. Esta acción no se puede deshacer.`, "Emitir voto")) return;
    await withBusy(b, async () => {
      const { error: err } = await sb.rpc("cast_vote", { p_election: s.dataset.eid, p_list: sel.value || null });
      const title = $("h3", s).textContent;
      if (err && !String(err.message).includes("already_voted")) return showError(err);
      if (err) toast("Ya registraste tu voto en esta votación.", "err"); else toast("Voto registrado.");
      s.outerHTML = doneHTML(title);
    });
  });
}

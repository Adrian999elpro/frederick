// Administración de votaciones: crear, agregar listas con foto del presidente, abrir y cerrar.
import { sb, esc, toast, showError, confirmBox, fmtDate, photoUrls, initials, withBusy, $, $$ } from "../core.js?v=20261018-community";

const STATUS = { draft: ["Borrador", "warn"], open: ["Abierta", "ok"], closed: ["Cerrada", ""] };
const TYPES = { "image/jpeg": "jpg", "image/png": "png", "image/webp": "webp" };
const MAX_BYTES = 2 * 1024 * 1024;
const BUCKET = "election-photos";

const card = (e) => `<article class="card" data-id="${esc(e.id)}">
  <div class="row"><h3>${esc(e.title)}</h3><span class="badge ${STATUS[e.status][1]}">${STATUS[e.status][0]}</span></div>
  <p class="muted">${esc(fmtDate(e.starts_at))} — ${esc(fmtDate(e.ends_at))}</p>
  ${e.description ? `<p>${esc(e.description)}</p>` : ""}
  <div class="row"><button class="btn ghost sm" data-act="lists">Listas</button>
    ${e.status === "draft" ? `<button class="btn primary sm" data-act="open">Abrir votación</button><button class="btn danger sm" data-act="delete">Eliminar</button>` : ""}
    ${e.status === "open" ? `<button class="btn primary sm" data-act="close">Cerrar votación</button>` : ""}</div></article>`;

export async function render(root) {
  let selected = null;
  await draw();

  async function draw() {
    const { data, error } = await sb.from("elections").select("id,title,description,starts_at,ends_at,status").order("created_at", { ascending: false });
    if (error) return showError(error);
    root.innerHTML = `<h2>Votaciones</h2>
    <form id="f-new" class="card form">
      <h3>Nueva votación</h3>
      <label>Título<input name="title" required minlength="3" maxlength="120" placeholder="Consejo Estudiantil 2026-2027"></label>
      <label>Descripción<textarea name="description" maxlength="500"></textarea></label>
      <div class="row"><label>Inicio<input name="starts" type="datetime-local" required></label><label>Cierre<input name="ends" type="datetime-local" required></label></div>
      <div><button class="btn primary" type="submit">Crear en borrador</button></div>
    </form>
    <div class="stack" id="cards">${data.map(card).join("") || `<p class="muted">Aún no hay votaciones.</p>`}</div>
    <div id="detail"></div>`;

    $("#f-new", root).addEventListener("submit", async (ev) => {
      ev.preventDefault(); const f = ev.currentTarget;
      const starts = new Date(f.starts.value), ends = new Date(f.ends.value);
      if (!(ends > starts)) return toast("El cierre debe ser posterior al inicio.", "err");
      await withBusy($("[type=submit]", f), async () => {
        const { error: err } = await sb.from("elections").insert({ title: f.elements.namedItem("title").value.trim(), description: f.elements.namedItem("description").value.trim(),
          starts_at: starts.toISOString(), ends_at: ends.toISOString() });
        if (err) return showError(err); toast("Votación creada en borrador."); draw();
      });
    });

    $("#cards", root).addEventListener("click", async (ev) => {
      const b = ev.target.closest("button[data-act]"); if (!b) return;
      const id = b.closest("article").dataset.id;
      try {
        if (b.dataset.act === "lists") { selected = id; return drawDetail(data.find((x) => x.id === id)); }
        if (b.dataset.act === "open") {
          const { count } = await sb.from("election_lists").select("id", { count: "exact", head: true }).eq("election_id", id);
          if (!count) return toast("Agrega al menos una lista antes de abrir la votación.", "err");
          if (!await confirmBox("Al abrir la votación ya no podrás cambiar listas ni fechas. ¿Abrirla?", "Abrir")) return;
          await update(id, { status: "open" }, "Votación abierta.");
        } else if (b.dataset.act === "close") {
          if (!await confirmBox("Se cerrará la votación y se publicarán los resultados. No se puede reabrir. ¿Cerrarla?", "Cerrar")) return;
          await update(id, { status: "closed" }, "Votación cerrada.");
        } else if (b.dataset.act === "delete") {
          if (!await confirmBox("Se eliminará el borrador con todas sus listas. ¿Continuar?", "Eliminar")) return;
          const { data: ls } = await sb.from("election_lists").select("president_photo").eq("election_id", id);
          const paths = (ls ?? []).map((l) => l.president_photo).filter(Boolean);
          const { error: err } = await sb.from("elections").delete().eq("id", id);
          if (err) throw err;
          if (paths.length) await sb.storage.from(BUCKET).remove(paths);
          if (selected === id) selected = null; toast("Votación eliminada."); draw();
        }
      } catch (err) { showError(err); }
    });

    if (selected) { const e = data.find((x) => x.id === selected); if (e) await drawDetail(e); }
  }

  async function update(id, patch, okMsg) {
    const { error } = await sb.from("elections").update(patch).eq("id", id);
    if (error) throw error; toast(okMsg); draw();
  }

  async function drawDetail(e) {
    const box = $("#detail", root);
    const { data: lists, error } = await sb.from("election_lists").select("id,number,name,slogan,president_name,president_photo").eq("election_id", e.id).order("number");
    if (error) return showError(error);
    const urls = await photoUrls(lists.map((l) => l.president_photo));
    const editable = e.status === "draft";
    box.innerHTML = `<div class="card"><h3>Listas de «${esc(e.title)}»</h3>
      <div class="table-wrap"><table class="table"><thead><tr><th>Foto</th><th>N.º</th><th>Lista</th><th>Presidente/a</th><th>Lema</th>${editable ? "<th></th>" : ""}</tr></thead><tbody>
      ${lists.map((l) => `<tr data-id="${esc(l.id)}" data-photo="${esc(l.president_photo ?? "")}">
        <td>${urls[l.president_photo] ? `<img class="photo sm" src="${esc(urls[l.president_photo])}" alt="Foto de ${esc(l.president_name)}">` : `<span class="photo sm" aria-hidden="true">${esc(initials(l.president_name))}</span>`}</td>
        <td>${l.number}</td><td>${esc(l.name)}</td><td>${esc(l.president_name)}</td><td>${esc(l.slogan)}</td>
        ${editable ? `<td class="actions"><button class="btn danger sm" data-del>Quitar</button></td>` : ""}</tr>`).join("") || `<tr><td colspan="6" class="muted">Sin listas todavía.</td></tr>`}
      </tbody></table></div>
      ${editable ? `<form id="f-list" class="form"><h3>Agregar lista</h3>
        <div class="row"><label>N.º<input name="number" type="number" min="1" max="99" required></label>
          <label>Nombre de la lista<input name="name" required maxlength="80"></label></div>
        <div class="row"><label>Presidente/a<input name="president" required maxlength="80"></label>
          <label>Lema<input name="slogan" maxlength="160"></label></div>
        <label>Foto del presidente/a (JPG, PNG o WebP, hasta 2 MB)<input name="photo" type="file" accept="image/jpeg,image/png,image/webp"></label>
        <div><button class="btn primary" type="submit">Agregar lista</button></div></form>`
        : `<p class="hint">Las listas no se pueden modificar una vez abierta la votación.</p>`}</div>`;
    box.scrollIntoView({ behavior: "smooth", block: "nearest" });
    if (!editable) return;

    $("tbody", box).addEventListener("click", async (ev) => {
      const b = ev.target.closest("[data-del]"); if (!b) return;
      const tr = b.closest("tr");
      if (!await confirmBox("¿Quitar esta lista?", "Quitar")) return;
      const { error: err } = await sb.from("election_lists").delete().eq("id", tr.dataset.id);
      if (err) return showError(err);
      if (tr.dataset.photo) await sb.storage.from(BUCKET).remove([tr.dataset.photo]);
      drawDetail(e);
    });

    $("#f-list", box).addEventListener("submit", async (ev) => {
      ev.preventDefault(); const f = ev.currentTarget; const file = f.photo.files[0];
      if (file && !TYPES[file.type]) return toast("La foto debe ser JPG, PNG o WebP.", "err");
      if (file && file.size > MAX_BYTES) return toast("La foto no puede superar 2 MB.", "err");
      await withBusy($("[type=submit]", f), async () => {
        let path = null;
        if (file) {
          path = `${e.id}/${crypto.randomUUID()}.${TYPES[file.type]}`;
          const up = await sb.storage.from(BUCKET).upload(path, file, { contentType: file.type, upsert: false });
          if (up.error) return showError(up.error);
        }
        const { error: err } = await sb.from("election_lists").insert({ election_id: e.id, number: Number(f.number.value),
          name: f.elements.namedItem("name").value.trim(), slogan: f.slogan.value.trim(), president_name: f.president.value.trim(), president_photo: path });
        if (err) { if (path) await sb.storage.from(BUCKET).remove([path]); return showError(err, err.code === "23505" ? "Ya existe una lista con ese número." : undefined); }
        toast("Lista agregada."); drawDetail(e);
      });
    });
  }
}

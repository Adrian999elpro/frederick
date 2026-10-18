// Vista: Cartelera de Novedades y Anuncios Institucionales FWT
// Publicaciones oficiales de Rectores, Directores y Profesores
import { sb, $, $$, esc, toast, confirmBox, withBusy, showError } from "../core.js?v=20261018-community";

export async function render(root, access) {
  const canPublish = !access.terminal && (access.permissions.includes("announcements.manage") || access.role === "admin");

  root.innerHTML = `
    <header class="row" style="justify-content: space-between; margin-bottom: 1.5rem;">
      <div>
        <h2 style="color: var(--brand-text); margin: 0;">📢 Novedades y Anuncios Institucionales</h2>
        <p class="muted" style="margin: 4px 0 0;">Comunicados oficiales de Rectorado, Direcciones de Área y Docentes</p>
      </div>
      ${canPublish ? `<button id="btn-new-announcement" class="btn primary sm">+ Publicar Anuncio</button>` : ''}
    </header>

    <div class="row" style="margin-bottom: 1.5rem; gap: 0.5rem;">
      <button class="btn ghost sm filter-btn active" data-category="">Todos</button>
      <button class="btn ghost sm filter-btn" data-category="urgente">🚨 Urgentes</button>
      <button class="btn ghost sm filter-btn" data-category="academico">📘 Académicos</button>
      <button class="btn ghost sm filter-btn" data-category="evento">🎉 Eventos</button>
      <button class="btn ghost sm filter-btn" data-category="general">📌 General</button>
    </div>

    <!-- Lista de Anuncios -->
    <div id="announcements-container" class="stack">
      <p class="muted center">Cargando anuncios escolares...</p>
    </div>

    <!-- Modal para Publicar Anuncio -->
    <dialog id="dlg-announcement" class="dlg" style="max-width: 32rem;">
      <h3 style="margin-top: 0; color: var(--brand-text);">Publicar Anuncio Institucional</h3>
      <form id="f-announcement" class="form">
        <label>Título del Comunicado
          <input name="title" required placeholder="Ej: Horarios de Exámenes del 1er Quimestre">
        </label>
        <div class="row" style="gap: 1rem;">
          <label style="flex: 1;">Categoría
            <select name="category" required>
              <option value="general">General</option>
              <option value="academico">Académico</option>
              <option value="evento">Evento Institucional</option>
              <option value="urgente">Urgente / Importante</option>
            </select>
          </label>
          <label style="flex: 1;">Firma / Cargo
            <input name="author_role_title" required value="${access.role === 'admin' ? 'Rectorado' : access.role === 'docente' ? 'Docente' : 'Dirección'}">
          </label>
        </div>
        <label>Dirigido a
          <select name="target_level_id" id="sel-target-level">
            <option value="">Todo el Plantel (8vo a 3ro Bachillerato)</option>
          </select>
        </label>
        <label>Contenido del Mensaje
          <textarea name="content" required placeholder="Escriba aquí los detalles del comunicado..."></textarea>
        </label>
        <label class="row" style="font-weight: normal; cursor: pointer; margin-top: 0.25rem;">
          <input type="checkbox" name="is_pinned">
          <span>Fijar este anuncio en la parte superior</span>
        </label>
        <div class="row end" style="margin-top: 1rem;">
          <button type="button" class="btn ghost sm" id="btn-cancel-announcement">Cancelar</button>
          <button type="submit" class="btn primary sm">Publicar Ahora</button>
        </div>
      </form>
    </dialog>
  `;

  const container = $("#announcements-container", root);
  const dlg = $("#dlg-announcement", root);
  let activeFilter = "";

  // Cargar grados en el select
  try {
    const { data: levels } = await sb.from("school_levels").select("id, name").order("order_index");
    const targetSelect = $("#sel-target-level", root);
    (levels || []).forEach(l => targetSelect.appendChild(new Option(l.name, l.id)));
  } catch (e) {}

  async function loadAnnouncements() {
    container.innerHTML = `<p class="muted center">Cargando anuncios...</p>`;

    let query = sb
      .from("announcements")
      .select("*, profiles(full_name, email), school_levels(name)")
      .order("is_pinned", { ascending: false })
      .order("created_at", { ascending: false });

    if (activeFilter) {
      query = query.eq("category", activeFilter);
    }

    const { data, error } = await query;
    if (error) {
      container.innerHTML = `<p class="callout err">Error al cargar anuncios: ${esc(error.message)}</p>`;
      return;
    }

    if (!data || data.length === 0) {
      container.innerHTML = `
        <div class="card center muted" style="padding: 3rem;">
          <p style="font-size: 1.1rem; margin-bottom: 0.5rem;">📭 No hay comunicados en esta categoría.</p>
          <p class="hint">Las novedades publicadas por rectorado y docentes aparecerán aquí.</p>
        </div>
      `;
      return;
    }

    container.innerHTML = data.map(item => {
      let catBadge = "badge";
      let catLabel = "General";
      let cardClass = "";

      if (item.category === 'urgente') {
        catBadge = "badge red"; catLabel = "🚨 URGENTE"; cardClass = "urgent";
      } else if (item.category === 'academico') {
        catBadge = "badge blue"; catLabel = "📘 Académico"; cardClass = "academico";
      } else if (item.category === 'evento') {
        catBadge = "badge warn"; catLabel = "🎉 Evento"; cardClass = "evento";
      }

      const dateStr = new Date(item.created_at).toLocaleDateString("es-EC", {
        day: "numeric", month: "long", year: "numeric", hour: "2-digit", minute: "2-digit"
      });

      const authorName = item.profiles?.full_name || item.profiles?.email || 'Institucional';
      const targetLabel = item.school_levels?.name ? `Dirigido a: <b>${esc(item.school_levels.name)}</b>` : 'Dirigido a: <b>Todo el Colegio</b>';

      const canDelete = !access.terminal && (access.role === 'admin' || access.id === item.author_id);

      return `
        <article class="announcement-card ${cardClass}">
          <div class="announcement-header">
            <div>
              <div style="display:flex; align-items:center; gap:8px; margin-bottom:4px;">
                ${item.is_pinned ? `<span class="badge" style="background:var(--danger-bg); color:var(--danger);">📌 FIJADO</span>` : ''}
                <span class="${catBadge}">${catLabel}</span>
                <span class="announcement-meta">${dateStr}</span>
              </div>
              <h3 style="margin: 4px 0; color: var(--text);">${esc(item.title)}</h3>
            </div>
            ${canDelete ? `
              <button class="btn danger sm btn-delete-ann" data-id="${item.id}" title="Eliminar comunicado">✕</button>
            ` : ''}
          </div>

          <div style="font-size: 0.95rem; line-height: 1.6; white-space: pre-wrap; margin: 10px 0; color: var(--text);">
            ${esc(item.content)}
          </div>

          <div class="announcement-meta" style="justify-content: space-between; border-top: 1px solid var(--line); padding-top: 8px; margin-top: 10px;">
            <span>${targetLabel}</span>
            <span>Firmado por: <b>${esc(authorName)}</b> (${esc(item.author_role_title)})</span>
          </div>
        </article>
      `;
    }).join("");

    $$(".btn-delete-ann", container).forEach(btn => {
      btn.addEventListener("click", async () => {
        if (!await confirmBox("¿Deseas eliminar este comunicado?")) return;
        const { error } = await sb.from("announcements").delete().eq("id", btn.dataset.id);
        if (error) showError(error);
        else { toast("Anuncio eliminado"); await loadAnnouncements(); }
      });
    });
  }

  // Filtrado por categoría
  $$(".filter-btn", root).forEach(btn => {
    btn.addEventListener("click", () => {
      $$(".filter-btn", root).forEach(b => b.classList.remove("active"));
      btn.classList.add("active");
      activeFilter = btn.dataset.category;
      loadAnnouncements();
    });
  });

  if (canPublish) {
    $("#btn-new-announcement", root).addEventListener("click", () => dlg.showModal());
    $("#btn-cancel-announcement", root).addEventListener("click", () => dlg.close());

    $("#f-announcement", root).addEventListener("submit", async (e) => {
      e.preventDefault();
      const form = e.target;
      const btn = $("button[type=submit]", form);
      await withBusy(btn, async () => {
        const payload = {
          title: form.elements.namedItem("title").value.trim(),
          content: form.content.value.trim(),
          category: form.category.value,
          author_role_title: form.author_role_title.value.trim(),
          target_level_id: form.target_level_id.value || null,
          is_pinned: form.is_pinned.checked,
          author_id: access.id
        };

        const { error } = await sb.from("announcements").insert(payload);
        if (error) showError(error);
        else {
          toast("Anuncio publicado exitosamente");
          form.reset();
          dlg.close();
          await loadAnnouncements();
        }
      });
    });
  }

  await loadAnnouncements();
}

// Vista: Administración de Tarjetas NFC / RFID
// Vinculación a cuentas de usuario y definición de rangos institucionales
import { sb, $, $$, esc, toast, confirmBox, withBusy, showError } from "../core.js?v=20261018-community";

export async function render(root, access) {
  const canManage = access.permissions.includes("nfc.manage") || access.role === "admin";

  root.innerHTML = `
    <header class="row" style="justify-content: space-between; margin-bottom: 1.5rem;">
      <div>
        <h2 style="color: var(--brand-text); margin: 0;">💳 Control de Tarjetas NFC / RFID</h2>
        <p class="muted" style="margin: 4px 0 0;">Vincula tarjetas a cuentas de estudiantes o personal, y define su rango y privilegios</p>
      </div>
      ${canManage ? `<button id="btn-new-card" class="btn primary sm">+ Vincular Nueva Tarjeta</button>` : ''}
    </header>

    <div class="card">
      <div class="row" style="justify-content: space-between; margin-bottom: 1rem; gap: 1rem; flex-wrap: wrap;">
        <div class="row" style="gap: 8px; flex: 1;">
          <input type="search" id="search-card" placeholder="Buscar por UID, nombre, email o etiqueta..." style="max-width: 320px;">
          <select id="filter-rank" style="width: auto; min-width: 190px;">
            <option value="">Todos los Rangos</option>
            <option value="admin">🔑 Administrador (Master Kiosko)</option>
            <option value="directivo">🏛️ Directivo / Rector</option>
            <option value="docente">👨‍🏫 Docente</option>
            <option value="estudiante">🎓 Estudiante</option>
          </select>
        </div>
        <span class="hint muted" id="card-count" style="align-self: center;">0 tarjetas registradas</span>
      </div>

      <div class="table-wrap">
        <table class="table">
          <thead>
            <tr>
              <th>UID Tarjeta</th>
              <th>Cuenta Vinculada</th>
              <th>Rango de la Tarjeta</th>
              <th>Rol en Sistema</th>
              <th>Estado</th>
              <th>Fecha Registro</th>
              ${canManage ? `<th class="actions">Acciones</th>` : ''}
            </tr>
          </thead>
          <tbody id="cards-tbody">
            <tr><td colspan="7" class="center muted">Cargando tarjetas NFC...</td></tr>
          </tbody>
        </table>
      </div>
    </div>

    <!-- Modal para Vincular / Editar Tarjeta -->
    <dialog id="dlg-card" class="dlg" style="max-width: 30rem;">
      <h3 id="modal-card-title" style="margin-top: 0; color: var(--brand-text);">Vincular Tarjeta NFC</h3>
      <form id="f-card" class="form">
        <input type="hidden" name="card_id" id="form-card-id">

        <label>UID del Sensor NFC / RFID
          <input name="card_uid" id="form-card-uid" required placeholder="Ej: 04:A2:3B:5C o 1461937402" style="font-family: monospace; font-weight: 700; text-transform: uppercase;">
          <span class="hint">Identificador único hexadecimal o decimal del chip de la tarjeta.</span>
        </label>

        <label>Cuenta de Usuario a Vincular
          <select name="profile_id" required id="select-card-user" style="font-weight: 600;"></select>
          <span class="hint">Selecciona el estudiante, docente o directivo dueño de esta tarjeta.</span>
        </label>

        <label>Rango y Privilegio de la Tarjeta
          <select name="card_type" required id="select-card-type" style="font-weight: 700;">
            <option value="estudiante">🎓 Estudiante (Asistencia diaria y Votación escolar)</option>
            <option value="docente">👨‍🏫 Docente (Registro institucional y control docente)</option>
            <option value="directivo">🏛️ Directivo / Rectorado (Facultades de dirección)</option>
            <option value="admin">🔑 Administrador (Tarjeta Maestra: Salir de la App Kiosko)</option>
          </select>
          <span class="hint" id="rank-hint" style="color: var(--brand-text);">
            Rango para definir qué funciones activa la tarjeta en el lector.
          </span>
        </label>

        <label>Etiqueta o Nota Identificativa (Opcional)
          <input name="label" id="form-card-label" placeholder="Ej: Carnet Estudiantil #042, Carnet Rectoría">
        </label>

        <label class="row" style="font-weight: normal; cursor: pointer;">
          <input type="checkbox" name="active" id="form-card-active" checked>
          <span><b>Tarjeta Activa</b> (Habilitada en los lectores)</span>
        </label>

        <div class="row end" style="margin-top: 1rem;">
          <button type="button" class="btn ghost sm" id="btn-cancel-card">Cancelar</button>
          <button type="submit" class="btn primary sm" id="btn-submit-card">Guardar Vinculación</button>
        </div>
      </form>
    </dialog>
  `;

  const tbody = $("#cards-tbody", root);
  const dlg = $("#dlg-card", root);
  const searchInput = $("#search-card", root);
  const filterRank = $("#filter-rank", root);
  const formCard = $("#f-card", root);

  let allCards = [];
  let allUsers = [];

  async function loadUsers() {
    const { data: users } = await sb
      .from("profiles")
      .select("id, full_name, email, roles(name), student_details(school_levels(name))")
      .eq("status", "active")
      .order("full_name");

    allUsers = users || [];
    const sel = $("#select-card-user", root);
    sel.innerHTML = allUsers.map(u => {
      const name = u.full_name || u.email;
      const role = u.roles?.name || 'usuario';
      const level = u.student_details?.school_levels?.name ? ` - ${u.student_details.school_levels.name}` : '';
      return `<option value="${u.id}">${esc(name)} [${esc(role.toUpperCase())}${esc(level)}]</option>`;
    }).join("");
  }

  async function loadCards() {
    tbody.innerHTML = `<tr><td colspan="7" class="center muted">Cargando...</td></tr>`;
    const { data, error } = await sb
      .from("nfc_cards")
      .select("*, profiles(full_name, email, roles(name), student_details(school_levels(name)))")
      .order("created_at", { ascending: false });

    if (error) {
      tbody.innerHTML = `<tr><td colspan="7" class="center" style="color:var(--danger)">${esc(error.message)}</td></tr>`;
      return;
    }

    allCards = data || [];
    applyFilters();
  }

  function applyFilters() {
    const term = searchInput.value.toLowerCase().trim();
    const rank = filterRank.value;

    let filtered = allCards;
    if (rank) {
      filtered = filtered.filter(c => c.card_type === rank);
    }
    if (term) {
      filtered = filtered.filter(c =>
        c.card_uid.toLowerCase().includes(term) ||
        (c.label && c.label.toLowerCase().includes(term)) ||
        (c.profiles?.full_name && c.profiles.full_name.toLowerCase().includes(term)) ||
        (c.profiles?.email && c.profiles.email.toLowerCase().includes(term))
      );
    }

    $("#card-count", root).textContent = `${filtered.length} de ${allCards.length} tarjetas`;
    renderCards(filtered);
  }

  function renderCards(list) {
    if (list.length === 0) {
      tbody.innerHTML = `<tr><td colspan="7" class="center muted" style="padding:2.5rem;">No se encontraron tarjetas con los criterios seleccionados.</td></tr>`;
      return;
    }

    tbody.innerHTML = list.map(c => {
      let rankBadge = `<span class="badge">🎓 Estudiante</span>`;
      if (c.card_type === 'admin') {
        rankBadge = `<span class="badge" style="background:var(--danger-bg); color:var(--danger); font-weight:800;">🔑 ADMIN (Master Kiosko)</span>`;
      } else if (c.card_type === 'directivo') {
        rankBadge = `<span class="badge purple" style="font-weight:700;">🏛️ Directivo / Rector</span>`;
      } else if (c.card_type === 'docente') {
        rankBadge = `<span class="badge blue" style="font-weight:700;">👨‍🏫 Docente</span>`;
      }

      const userName = c.profiles?.full_name || c.profiles?.email || 'Sin usuario asignado';
      const userLevel = c.profiles?.student_details?.school_levels?.name ? `<div class="hint blue" style="font-size:0.8rem; color:var(--info);">${esc(c.profiles.student_details.school_levels.name)}</div>` : '';

      return `
        <tr data-id="${c.id}">
          <td><code style="font-weight:700; color: var(--brand-text); font-size:0.95rem;">${esc(c.card_uid)}</code></td>
          <td>
            <strong>${esc(userName)}</strong>
            ${userLevel}
            ${c.label ? `<div class="hint muted" style="font-style:italic;">Nota: ${esc(c.label)}</div>` : ''}
          </td>
          <td>${rankBadge}</td>
          <td><span class="badge">${esc(c.profiles?.roles?.name?.toUpperCase() || '---')}</span></td>
          <td>
            <span class="badge ${c.active ? 'ok' : 'off'}">
              ${c.active ? 'Activa' : 'Desactivada'}
            </span>
          </td>
          <td><span class="muted" style="font-size:0.85rem;">${new Date(c.created_at).toLocaleDateString("es-EC")}</span></td>
          ${canManage ? `
            <td class="actions">
              <button class="btn ghost sm btn-edit-card" data-id="${c.id}" title="Cambiar cuenta o rango">✏️ Rango</button>
              <button class="btn ghost sm btn-toggle-card" data-id="${c.id}" data-active="${c.active}">
                ${c.active ? 'Desactivar' : 'Activar'}
              </button>
              <button class="btn danger sm btn-del-card" data-id="${c.id}" title="Eliminar tarjeta">✕</button>
            </td>` : ''}
        </tr>
      `;
    }).join("");

    if (canManage) {
      // Editar / Cambiar Rango y Vinculación
      $$(".btn-edit-card", tbody).forEach(btn => {
        btn.addEventListener("click", () => {
          const cardId = btn.dataset.id;
          const card = allCards.find(c => c.id === cardId);
          if (!card) return;

          $("#modal-card-title", root).textContent = "Editar Tarjeta y Definir Rango";
          $("#form-card-id", root).value = card.id;
          $("#form-card-uid", root).value = card.card_uid;
          $("#form-card-uid", root).readOnly = true; // No cambiar UID para no romper sensor
          $("#select-card-user", root).value = card.profile_id || "";
          $("#select-card-type", root).value = card.card_type || "estudiante";
          $("#form-card-label", root).value = card.label || "";
          $("#form-card-active", root).checked = card.active;
          $("#btn-submit-card", root).textContent = "Guardar Cambios";

          dlg.showModal();
        });
      });

      // Alternar Activa/Inactiva
      $$(".btn-toggle-card", tbody).forEach(btn => {
        btn.addEventListener("click", async () => {
          const newActive = btn.dataset.active !== "true";
          const { error } = await sb.from("nfc_cards").update({ active: newActive }).eq("id", btn.dataset.id);
          if (error) showError(error);
          else { toast(newActive ? "Tarjeta activada" : "Tarjeta desactivada"); await loadCards(); }
        });
      });

      // Eliminar tarjeta
      $$(".btn-del-card", tbody).forEach(btn => {
        btn.addEventListener("click", async () => {
          if (!await confirmBox("¿Deseas desvincular y eliminar esta tarjeta?")) return;
          const { error } = await sb.from("nfc_cards").delete().eq("id", btn.dataset.id);
          if (error) showError(error);
          else { toast("Tarjeta eliminada"); await loadCards(); }
        });
      });
    }
  }

  searchInput.addEventListener("input", applyFilters);
  filterRank.addEventListener("change", applyFilters);

  if (canManage) {
    $("#btn-new-card", root).addEventListener("click", () => {
      $("#modal-card-title", root).textContent = "Vincular Nueva Tarjeta NFC";
      formCard.reset();
      $("#form-card-id", root).value = "";
      $("#form-card-uid", root).readOnly = false;
      $("#form-card-active", root).checked = true;
      $("#btn-submit-card", root).textContent = "Vincular y Guardar";
      dlg.showModal();
    });

    $("#btn-cancel-card", root).addEventListener("click", () => dlg.close());

    // Submit formulario (insert o update de vinculación)
    formCard.addEventListener("submit", async (e) => {
      e.preventDefault();
      const btn = $("#btn-submit-card", root);
      await withBusy(btn, async () => {
        const cardId = $("#form-card-id", root).value || null;
        const cardUid = $("#form-card-uid", root).value.trim().toUpperCase();
        const profileId = $("#select-card-user", root).value;
        const cardType = $("#select-card-type", root).value;
        const label = $("#form-card-label", root).value.trim();
        const active = $("#form-card-active", root).checked;

        // Llamar a RPC save_nfc_card_binding
        const { error } = await sb.rpc("save_nfc_card_binding", {
          p_card_id: cardId,
          p_card_uid: cardUid,
          p_profile_id: profileId,
          p_card_type: cardType,
          p_label: label,
          p_active: active
        });

        if (error) showError(error);
        else {
          toast(cardId ? "Tarjeta y rango actualizados exitosamente" : "Tarjeta NFC vinculada exitosamente");
          dlg.close();
          await loadCards();
        }
      });
    });
  }

  await Promise.all([loadUsers(), loadCards()]);
}

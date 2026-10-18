import { sb, CONFIG, esc, toast, showError, login, getAccess, withBusy, $, $$ } from "../core.js?v=20261018-community";

export async function render(root, access) {
  const isStudent = access.role === "estudiante";
  const isTeacher = access.role === "docente";

  root.innerHTML = `
    <header style="margin-bottom: 1.5rem;">
      <h2 style="color: var(--brand-text); margin: 0;">Mi Perfil Institucional</h2>
      <p class="muted" style="margin: 4px 0 0;">Información personal, especialidad técnica, personalización y seguridad</p>
    </header>

    ${access.must_change_password ? `<p class="callout warn">Tu cuenta usa una contraseña temporal. Cámbiala para continuar.</p>` : ""}

    <!-- INDICADOR DOCENTE: MATERIAS ASIGNADAS -->
    ${isTeacher ? `
      <section class="card" style="border-left: 5px solid var(--brand); margin-bottom: 1.5rem;">
        <h3 style="margin: 0 0 0.5rem; color: var(--brand-text);">👨‍🏫 Mis Asignaturas y Cursos Asignados</h3>
        <p class="hint muted" style="margin-bottom: 0.75rem;">Indicadores del plan docente para este año lectivo:</p>
        <div id="teacher-subjects-container" class="row">
          <span class="muted hint">Consultando materias asignadas...</span>
        </div>
      </section>
    ` : ''}

    <div class="grid-2">
      <!-- FORMULARIO 1: DATOS PERSONALES -->
      <form id="f-prof" class="card form">
        <h3>Datos Personales</h3>
        <label>Correo Electrónico<input value="${esc(access.email)}" disabled></label>
        <label>Nombre Completo<input name="full_name" maxlength="120" required value="${esc(access.full_name)}"></label>
        <label>Teléfono de Contacto<input name="phone" type="tel" maxlength="30" value="${esc(access.phone || '')}"></label>
        <p class="hint">Rol asignado: <strong>${esc(access.role.toUpperCase())}</strong></p>
        <button class="btn primary" type="submit">Guardar Datos Personales</button>
      </form>

      <!-- FORMULARIO 2: CUSTOMIZACIÓN Y ESPECIALIDADES ESTUDIANTE -->
      ${isStudent ? `
        <form id="f-student-custom" class="card form" style="border: 2px solid #e5e7eb;">
          <div class="row" style="justify-content: space-between; align-items: flex-start;">
            <h3 style="margin: 0; color: var(--brand-text);">🎨 Personalización de Estudiante</h3>
            <span class="badge blue" id="student-level-badge">Cargando grado...</span>
          </div>

          <label>Biografía / Frase Personal
            <textarea name="bio" maxlength="200" placeholder="Escribe algo sobre ti, tus metas o tu lema de estudio..."></textarea>
            <span class="hint">Visible en tu tarjeta y podio de honor.</span>
          </label>

          <label>Tema de Avatar
            <select name="avatar_theme">
              <option value="classic">Clásico Institucional (Azul/Rojo FWT)</option>
              <option value="tech">Técnico Científico</option>
              <option value="gold">Académico Destacado (Dorado)</option>
              <option value="modern">Moderno Minimalista</option>
            </select>
          </label>

          <!-- SECCIÓN DE ESPECIALIDAD: BACHILLERATO vs BÁSICA -->
          <div id="specialties-section" style="background: var(--surface-sunken); border: 1.5px solid var(--line); border-radius: 12px; padding: 1.1rem; margin-top: 0.5rem;">
            <div id="specialty-loading" class="muted hint">Cargando especialidades...</div>
            
            <!-- Vista para Bachillerato (1ro a 3ro) -->
            <div id="bachillerato-specialty-box" style="display: none;">
              <label style="font-weight: 800; color: var(--brand-text); margin-bottom: 6px;">
                🎓 Especialidad de Bachillerato Técnico Oficial:
              </label>
              <select name="chosen_specialty_id" id="sel-chosen-specialty" style="font-weight: 600;">
                <option value="">Selecciona tu especialidad técnica...</option>
              </select>
              <p class="hint" style="margin-top: 6px;">
                Especialidad técnica oficial cursada en la Unidad Educativa Técnica Particular Frederick Winslow Taylor.
              </p>
            </div>

            <!-- Vista para Básica (8vo, 9no, 10mo): Selección múltiple de gustos -->
            <div id="basica-specialty-box" style="display: none;">
              <label style="font-weight: 800; color: var(--brand-text); margin-bottom: 4px;">
                🎯 Orientación Vocacional (Educación Básica):
              </label>
              <p class="hint" style="margin-bottom: 10px;">
                ¿Qué especialidades te gustan o te llaman la atención para tu futuro Bachillerato Técnico? <b>Puedes elegir varias:</b>
              </p>
              <div id="checkboxes-interested" class="stack" style="gap: 8px;"></div>
            </div>
          </div>

          <!-- PRIVACIDAD DE NOTAS -->
          <div style="background: var(--surface-sunken); border: 1.5px solid var(--line); border-radius: 12px; padding: 1rem; margin-top: 0.5rem;">
            <label style="display:flex; flex-direction:column; gap:6px; cursor: pointer;">
              <span style="font-weight: 800; font-size: 0.95rem; color: var(--text);">Privacidad de Calificaciones:</span>
              <div class="row" style="gap: 1.5rem; margin-top: 4px;">
                <label class="row" style="font-weight: 600; cursor:pointer;">
                  <input type="radio" name="notes_visibility" value="public">
                  <span>🌐 <b>Públicas</b> (Participar en el Ranking escolar)</span>
                </label>
                <label class="row" style="font-weight: 600; cursor:pointer;">
                  <input type="radio" name="notes_visibility" value="private" checked>
                  <span>🔒 <b>Privadas</b> (Ocultas del Ranking)</span>
                </label>
              </div>
            </label>
            <p class="hint" style="margin-top: 8px;">
              Si eliges <b>Públicas</b>, tu promedio y tu especialidad aparecerán en el Ranking de Honor del colegio si calificas en los mejores puestos.
            </p>
          </div>

          <button class="btn primary" type="submit" style="margin-top: 0.5rem;">Guardar Mi Personalización</button>
        </form>
      ` : ''}

      <!-- FORMULARIO 3: CAMBIAR CONTRASEÑA -->
      <form id="f-pass" class="card form">
        <h3>Seguridad: Cambiar Contraseña</h3>
        <label>Contraseña Actual<input name="cur" type="password" autocomplete="current-password" required maxlength="128"></label>
        <label>Nueva Contraseña<input name="next" type="password" autocomplete="new-password" required minlength="${CONFIG.MIN_PASSWORD}" maxlength="128"></label>
        <label>Confirmar Nueva Contraseña<input name="again" type="password" autocomplete="new-password" required maxlength="128"></label>
        <p class="hint">Mínimo ${CONFIG.MIN_PASSWORD} caracteres.</p>
        <button class="btn ghost" type="submit">Actualizar Contraseña</button>
      </form>
    </div>
  `;

  // Cargar datos de docente
  if (isTeacher) {
    try {
      const { data: assignments } = await sb.rpc("get_teacher_assignments", { p_teacher_id: access.id });
      const container = $("#teacher-subjects-container", root);
      if (!assignments || assignments.length === 0) {
        container.innerHTML = `<span class="muted hint">Aún no tienes asignaturas registradas. El administrador o director te asignará materias.</span>`;
      } else {
        container.innerHTML = assignments.map(a => `
          <div class="teacher-chip" style="background: var(--surface); padding: 6px 14px; border: 1.5px solid var(--brand); box-shadow: var(--shadow-sm);">
            📘 <b>${esc(a.subject_name)}</b> &nbsp; <span class="badge blue">${esc(a.level_name)}</span>
          </div>
        `).join("");
      }
    } catch (e) {
      console.error(e);
    }
  }

  // Cargar personalización de estudiante
  if (isStudent) {
    try {
      // 1. Obtener especialidades disponibles
      const { data: specialties } = await sb
        .from("technical_specialties")
        .select("*")
        .order("name");

      const allSpecialties = specialties || [];

      // 2. Obtener detalle del estudiante
      const { data: detail } = await sb
        .from("student_details")
        .select("*, school_levels(id, name, code, order_index)")
        .eq("profile_id", access.id)
        .maybeSingle();

      const form = $("#f-student-custom", root);
      const loadingBox = $("#specialty-loading", root);
      const bachBox = $("#bachillerato-specialty-box", root);
      const basicaBox = $("#basica-specialty-box", root);
      const selChosen = $("#sel-chosen-specialty", root);
      const checkContainer = $("#checkboxes-interested", root);

      if (loadingBox) loadingBox.style.display = "none";

      const isBachillerato = detail?.school_levels?.code?.includes("BACH") || (detail?.school_levels?.order_index >= 4);

      if (detail && form) {
        form.bio.value = detail.bio || "";
        form.avatar_theme.value = detail.avatar_theme || "classic";
        const radio = form.querySelector(`input[name="notes_visibility"][value="${detail.notes_visibility}"]`);
        if (radio) radio.checked = true;
        if (detail.school_levels?.name) {
          $("#student-level-badge", root).textContent = detail.school_levels.name;
        }
      }

      // Poblado de especialidades
      if (isBachillerato) {
        bachBox.style.display = "block";
        allSpecialties.forEach(sp => {
          const opt = document.createElement("option");
          opt.value = sp.id;
          opt.textContent = `${sp.name} (${sp.short_name})`;
          if (detail?.chosen_specialty_id === sp.id) opt.selected = true;
          selChosen.appendChild(opt);
        });
      } else {
        // Estudiantes de 8vo, 9no, 10mo de Básica
        basicaBox.style.display = "block";
        const interestedList = detail?.interested_specialties || [];

        const specIcons = {
          mecanizado: "⚙️",
          software: "💻",
          automotriz: "🚗",
          musica: "🎵"
        };

        checkContainer.innerHTML = allSpecialties.map(sp => {
          const icon = specIcons[sp.code] || "📘";
          const isChecked = interestedList.includes(sp.code);
          return `
            <label style="display:flex; align-items:center; gap:10px; background: var(--surface); padding:8px 12px; border:1px solid var(--line); border-radius:8px; cursor:pointer;">
              <input type="checkbox" name="interested_spec" value="${esc(sp.code)}" ${isChecked ? 'checked' : ''}>
              <span style="font-size:1.2rem;">${icon}</span>
              <div>
                <strong style="color:var(--text);">${esc(sp.name)}</strong>
                <div class="hint muted" style="font-size:0.8rem;">${esc(sp.description)}</div>
              </div>
            </label>
          `;
        }).join("");
      }

    } catch (e) {
      console.error(e);
    }

    $("#f-student-custom", root)?.addEventListener("submit", async (e) => {
      e.preventDefault();
      const f = e.currentTarget;
      const btn = $("[type=submit]", f);
      await withBusy(btn, async () => {
        // 1. Guardar bio, avatar, visibilidad
        const payloadCustom = {
          p_bio: f.bio.value.trim(),
          p_avatar_theme: f.avatar_theme.value,
          p_notes_visibility: f.notes_visibility.value
        };
        const { error: err1 } = await sb.rpc("update_student_custom_profile", payloadCustom);
        if (err1) return showError(err1);

        // 2. Guardar especialidad o intereses de básica
        const chosenId = f.chosen_specialty_id ? (f.chosen_specialty_id.value || null) : null;
        const interestedBoxes = $$('input[name="interested_spec"]:checked', f);
        const interestedArray = Array.from(interestedBoxes).map(cb => cb.value);

        const { error: err2 } = await sb.rpc("update_student_specialties", {
          p_chosen_specialty_id: chosenId,
          p_interested_specialties: interestedArray
        });

        if (err2) showError(err2);
        else toast("Personalización y especialidades guardadas con éxito.");
      });
    });
  }

  // Guardar datos personales
  $("#f-prof", root).addEventListener("submit", async (e) => {
    e.preventDefault(); const f = e.currentTarget;
    await withBusy($("[type=submit]", f), async () => {
      const { error } = await sb.from("profiles").update({
        full_name: f.full_name.value.trim(),
        phone: f.phone.value.trim() || null
      }).eq("id", access.id);

      if (error) return showError(error);
      await getAccess(true); toast("Perfil actualizado.");
    });
  });

  // Cambiar contraseña
  $("#f-pass", root).addEventListener("submit", async (e) => {
    e.preventDefault(); const f = e.currentTarget;
    if (f.next.value !== f.again.value) return toast("Las contraseñas nuevas no coinciden.", "err");
    if (f.next.value === f.cur.value) return toast("La nueva contraseña debe ser distinta de la actual.", "err");
    await withBusy($("[type=submit]", f), async () => {
      try {
        await login(access.email, f.cur.value);
        const { error } = await sb.auth.updateUser({ password: f.next.value });
        if (error) throw error;
        await sb.rpc("ack_password_changed");
        f.reset(); toast("Contraseña actualizada.");
        if (access.must_change_password) location.reload();
      } catch (err) { showError(err, "No se pudo cambiar la contraseña. Verifica la contraseña actual."); }
    });
  });
}

// Vista: Materias Configurables y Asignación de Profesores (Indicadores Docentes)
import { sb, $, $$, esc, toast, confirmBox, withBusy, showError } from "../core.js?v=20261018-community";

export async function render(root, access) {
  const canManage = access.permissions.includes("grades.manage") || access.role === "admin";

  root.innerHTML = `
    <header class="row" style="justify-content: space-between; margin-bottom: 1.5rem;">
      <div>
        <h2 style="color: var(--brand-text); margin: 0;">📚 Materias y Profesores Asignados</h2>
        <p class="muted" style="margin: 4px 0 0;">Configuración de asignaturas (Tronco Común y Especialidades Técnicas) y carga docente</p>
      </div>
      ${canManage ? `<button id="btn-new-subject" class="btn primary sm">+ Nueva Materia</button>` : ''}
    </header>

    <div class="grid-2">
      <!-- Columna 1: Materias por Grado y Especialidad -->
      <section class="card">
        <div class="row" style="justify-content: space-between; margin-bottom: 1rem;">
          <h3 style="margin: 0;">Asignaturas</h3>
          <div class="row" style="gap: 6px;">
            <select id="filter-level" style="width: auto; min-width: 150px;">
              <option value="">Todos los Grados</option>
            </select>
            <select id="filter-specialty" style="width: auto; min-width: 150px;">
              <option value="">Todas las Áreas</option>
              <option value="common">Tronco Común</option>
            </select>
          </div>
        </div>
        <div class="table-wrap">
          <table class="table">
            <thead>
              <tr>
                <th>Código</th>
                <th>Materia</th>
                <th>Área / Especialidad</th>
                <th>Grado</th>
                <th>Docentes</th>
                ${canManage ? `<th class="actions">Acción</th>` : ''}
              </tr>
            </thead>
            <tbody id="subjects-tbody">
              <tr><td colspan="${canManage ? 6 : 5}" class="center muted">Cargando materias...</td></tr>
            </tbody>
          </table>
        </div>
      </section>

      <!-- Columna 2: Indicadores de Profesores y Asignación -->
      <section class="card">
        <h3 style="margin-bottom: 0.5rem;">👨‍🏫 Indicadores de Profesores</h3>
        <p class="muted hint" style="margin-bottom: 1rem;">Detalle de asignaturas y cursos que imparte cada profesor del colegio</p>

        <div id="teachers-list" class="stack">
          <p class="muted center">Cargando profesores...</p>
        </div>
      </section>
    </div>

    <!-- Modal para Nueva Materia -->
    <dialog id="dlg-subject" class="dlg">
      <h3 style="margin-top: 0; color: var(--brand-text);">Registrar Materia</h3>
      <form id="f-subject" class="form">
        <label>Grado Escolar
          <select name="level_id" required id="select-modal-level"></select>
        </label>
        <label>Especialidad Técnica (Opcional)
          <select name="specialty_id" id="select-modal-specialty">
            <option value="">Tronco Común (Matemáticas, Lengua, etc.)</option>
          </select>
        </label>
        <label>Nombre de la Materia
          <input name="name" required placeholder="Ej: Programación y Bases de Datos, Soldadura...">
        </label>
        <label>Código Corto
          <input name="code" required placeholder="Ej: SOFT-PBD-1B, MECA-TOR" style="text-transform: uppercase;">
        </label>
        <label>Descripción (Opcional)
          <textarea name="description" placeholder="Objetivos o detalles del currículo"></textarea>
        </label>
        <div class="row end" style="margin-top: 1rem;">
          <button type="button" class="btn ghost sm" id="btn-cancel-subject">Cancelar</button>
          <button type="submit" class="btn primary sm">Guardar Materia</button>
        </div>
      </form>
    </dialog>

    <!-- Modal para Asignar Profesor a Materia -->
    <dialog id="dlg-assign" class="dlg">
      <h3 style="margin-top: 0; color: var(--brand-text);">Asignar Docente a Materia</h3>
      <p id="assign-subject-title" class="hint" style="font-weight: 700; margin-bottom: 1rem;"></p>
      <form id="f-assign" class="form">
        <input type="hidden" name="subject_id" id="assign-subject-id">
        <label>Seleccionar Profesor
          <select name="teacher_id" required id="select-assign-teacher"></select>
        </label>
        <div class="row end" style="margin-top: 1rem;">
          <button type="button" class="btn ghost sm" id="btn-cancel-assign">Cancelar</button>
          <button type="submit" class="btn primary sm">Asignar Docente</button>
        </div>
      </form>
    </dialog>
  `;

  const subjectsTbody = $("#subjects-tbody", root);
  const teachersList = $("#teachers-list", root);
  const filterLevel = $("#filter-level", root);
  const filterSpecialty = $("#filter-specialty", root);
  const dlgSubject = $("#dlg-subject", root);
  const dlgAssign = $("#dlg-assign", root);

  let levelsData = [];
  let teachersData = [];
  let specialtiesData = [];

  async function loadInitial() {
    try {
      // 1. Grados
      const { data: levels } = await sb.from("school_levels").select("*").order("order_index");
      levelsData = levels || [];
      levelsData.forEach(l => {
        filterLevel.appendChild(new Option(l.name, l.id));
        $("#select-modal-level", root).appendChild(new Option(l.name, l.id));
      });

      // 2. Especialidades
      const { data: specs } = await sb.from("technical_specialties").select("*").order("name");
      specialtiesData = specs || [];
      specialtiesData.forEach(s => {
        filterSpecialty.appendChild(new Option(s.short_name, s.id));
        $("#select-modal-specialty", root).appendChild(new Option(`Especialidad: ${s.name}`, s.id));
      });

      // 3. Profesores
      const { data: teachers } = await sb
        .from("profiles")
        .select("id, full_name, email, roles!inner(name)")
        .eq("roles.name", "docente")
        .eq("status", "active")
        .order("full_name");

      teachersData = teachers || [];
      const teacherSelect = $("#select-assign-teacher", root);
      teacherSelect.innerHTML = teachersData.map(t => `<option value="${t.id}">${esc(t.full_name || t.email)}</option>`).join("");

      await refreshAll();
    } catch (e) {
      showError(e);
    }
  }

  async function refreshAll() {
    await Promise.all([loadSubjects(), loadTeachersAssignments()]);
  }

  async function loadSubjects() {
    subjectsTbody.innerHTML = `<tr><td colspan="6" class="center muted">Cargando...</td></tr>`;
    let query = sb
      .from("subjects")
      .select("id, name, code, level_id, specialty_id, school_levels(name, code), technical_specialties(short_name, code), subject_teachers(profiles(id, full_name))")
      .order("name");

    if (filterLevel.value) {
      query = query.eq("level_id", filterLevel.value);
    }

    if (filterSpecialty.value === 'common') {
      query = query.is("specialty_id", null);
    } else if (filterSpecialty.value) {
      query = query.eq("specialty_id", filterSpecialty.value);
    }

    const { data, error } = await query;
    if (error) {
      subjectsTbody.innerHTML = `<tr><td colspan="6" class="center" style="color:var(--danger)">${esc(error.message)}</td></tr>`;
      return;
    }

    if (!data || data.length === 0) {
      subjectsTbody.innerHTML = `<tr><td colspan="6" class="center muted">No se encontraron materias registradas con este filtro.</td></tr>`;
      return;
    }

    subjectsTbody.innerHTML = data.map(sub => {
      const teachers = sub.subject_teachers?.map(st => st.profiles?.full_name).filter(Boolean) || [];
      const teachersChips = teachers.length > 0
        ? teachers.map(t => `<span class="badge ok">${esc(t)}</span>`).join(" ")
        : `<span class="hint muted">Sin docente asignado</span>`;

      const areaBadge = sub.technical_specialties?.short_name
        ? `<span class="badge red">🎓 ${esc(sub.technical_specialties.short_name)}</span>`
        : `<span class="badge">Tronco Común</span>`;

      return `
        <tr>
          <td><strong style="color: var(--brand-text);">${esc(sub.code)}</strong></td>
          <td><strong>${esc(sub.name)}</strong></td>
          <td>${areaBadge}</td>
          <td><span class="badge blue">${esc(sub.school_levels?.name || '')}</span></td>
          <td>${teachersChips}</td>
          ${canManage ? `
            <td class="actions">
              <button class="btn ghost sm btn-assign" data-id="${sub.id}" data-name="${esc(sub.name)}">+ Profesor</button>
              <button class="btn danger sm btn-del-sub" data-id="${sub.id}">✕</button>
            </td>` : ''}
        </tr>
      `;
    }).join("");

    if (canManage) {
      $$(".btn-assign", subjectsTbody).forEach(btn => {
        btn.addEventListener("click", () => {
          $("#assign-subject-id", root).value = btn.dataset.id;
          $("#assign-subject-title", root).textContent = `Materia: ${btn.dataset.name}`;
          dlgAssign.showModal();
        });
      });

      $$(".btn-del-sub", subjectsTbody).forEach(btn => {
        btn.addEventListener("click", async () => {
          if (!await confirmBox("¿Eliminar esta materia y sus calificaciones asociadas?")) return;
          const { error } = await sb.from("subjects").delete().eq("id", btn.dataset.id);
          if (error) showError(error);
          else { toast("Materia eliminada"); await refreshAll(); }
        });
      });
    }
  }

  async function loadTeachersAssignments() {
    teachersList.innerHTML = `<p class="muted center">Cargando indicadores...</p>`;
    const { data, error } = await sb.rpc("get_teacher_assignments");
    if (error) {
      teachersList.innerHTML = `<p class="callout err">Error al cargar asignaciones: ${esc(error.message)}</p>`;
      return;
    }

    const teacherMap = new Map();
    teachersData.forEach(t => {
      teacherMap.set(t.id, { name: t.full_name || t.email, subjects: [] });
    });

    (data || []).forEach(row => {
      if (!teacherMap.has(row.teacher_id)) {
        teacherMap.set(row.teacher_id, { name: row.teacher_name, subjects: [] });
      }
      teacherMap.get(row.teacher_id).subjects.push({
        subject_name: row.subject_name,
        subject_code: row.subject_code,
        level_name: row.level_name,
        subject_id: row.subject_id
      });
    });

    teachersList.innerHTML = Array.from(teacherMap.values()).map(t => {
      const count = t.subjects.length;
      return `
        <div style="padding: 0.9rem; border: 1px solid var(--line); border-radius: 10px; background: var(--surface);">
          <div class="row" style="justify-content: space-between; margin-bottom: 0.4rem;">
            <strong>${esc(t.name)}</strong>
            <span class="badge ${count > 0 ? 'blue' : 'warn'}">${count} ${count === 1 ? 'materia' : 'materias'}</span>
          </div>
          <div>
            ${count === 0 ? `<span class="hint muted">No tiene materias asignadas actualmente.</span>` :
              t.subjects.map(s => `
                <span class="teacher-chip" title="${esc(s.level_name)}">
                  📘 <b>${esc(s.subject_name)}</b> (${esc(s.level_name)})
                </span>
              `).join("")}
          </div>
        </div>
      `;
    }).join("");
  }

  filterLevel.addEventListener("change", loadSubjects);
  filterSpecialty.addEventListener("change", loadSubjects);

  if (canManage) {
    $("#btn-new-subject", root)?.addEventListener("click", () => dlgSubject.showModal());
    $("#btn-cancel-subject", root)?.addEventListener("click", () => dlgSubject.close());
    $("#btn-cancel-assign", root)?.addEventListener("click", () => dlgAssign.close());

    $("#f-subject", root)?.addEventListener("submit", async (e) => {
      e.preventDefault();
      const form = e.target;
      const btn = $("button[type=submit]", form);
      await withBusy(btn, async () => {
        const payload = {
          name: form.elements.namedItem("name").value.trim(),
          code: form.code.value.trim().toUpperCase(),
          level_id: form.level_id.value,
          specialty_id: form.specialty_id.value || null,
          description: form.elements.namedItem("description").value.trim()
        };
        const { error } = await sb.from("subjects").insert(payload);
        if (error) showError(error);
        else {
          toast("Materia creada correctamente");
          form.reset();
          dlgSubject.close();
          await refreshAll();
        }
      });
    });

    $("#f-assign", root)?.addEventListener("submit", async (e) => {
      e.preventDefault();
      const form = e.target;
      const btn = $("button[type=submit]", form);
      await withBusy(btn, async () => {
        const subject_id = form.subject_id.value;
        const teacher_id = form.teacher_id.value;
        const { error } = await sb.from("subject_teachers").upsert({ subject_id, teacher_id });
        if (error) showError(error);
        else {
          toast("Docente asignado con éxito");
          dlgAssign.close();
          await refreshAll();
        }
      });
    });
  }

  await loadInitial();
}

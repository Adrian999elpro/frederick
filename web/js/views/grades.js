// Vista: Calificaciones y Subida de Notas por Excel (CSV / XLSX)
import { sb, $, $$, esc, toast, withBusy, showError } from "../core.js";

export async function render(root, access) {
  const isTeacherOrAdmin = access.permissions.includes("grades.upload") || access.role === "admin";

  root.innerHTML = `
    <header class="row" style="justify-content: space-between; margin-bottom: 1.5rem;">
      <div>
        <h2 style="color: var(--brand-text); margin: 0;">📊 Calificaciones Académicas</h2>
        <p class="muted" style="margin: 4px 0 0;">Gestión de notas por materia, período y subida masiva vía Excel / CSV</p>
      </div>
      ${isTeacherOrAdmin ? `
        <div class="row">
          <button id="btn-show-upload" class="btn primary sm">📥 Subir Notas (Excel / CSV)</button>
        </div>` : ''}
    </header>

    <!-- Filtros de Búsqueda -->
    <div class="card" style="padding: 1.25rem;">
      <div class="row" style="gap: 1rem;">
        <label style="flex: 1; min-width: 200px;">Grado Escolar:
          <select id="sel-level"></select>
        </label>
        <label style="flex: 1; min-width: 200px;">Materia:
          <select id="sel-subject"><option value="">Seleccione grado primero</option></select>
        </label>
        <label style="flex: 1; min-width: 200px;">Período Académico:
          <select id="sel-period"></select>
        </label>
        <div style="align-self: flex-end;">
          <button id="btn-load-grades" class="btn ghost sm">🔍 Consultar</button>
        </div>
      </div>
    </div>

    <!-- Sección de Carga Masiva por Excel (Inicialmente oculta) -->
    ${isTeacherOrAdmin ? `
      <section id="upload-panel" class="card" style="display: none; border-left: 5px solid var(--brand); background: var(--surface-sunken);">
        <div class="row" style="justify-content: space-between; align-items: flex-start;">
          <div>
            <h3 style="margin: 0; color: var(--brand-text);">📥 Subida Masiva de Notas por Excel</h3>
            <p class="hint muted" style="margin-top: 4px;">
              Copia y pega directamente las columnas de tu Excel (<b>Código/Email, Calificación, Comentario</b>) o sube un archivo CSV.
            </p>
          </div>
          <button id="btn-close-upload" class="btn ghost sm">Cerrar</button>
        </div>

        <div class="stack" style="margin-top: 1rem;">
          <div class="row">
            <button id="btn-download-template" class="btn ghost sm">📄 Descargar Plantilla para este Curso (CSV)</button>
            <input type="file" id="file-csv" accept=".csv, text/csv, .txt" style="display: none;">
            <button id="btn-browse-file" class="btn ghost sm">📁 Cargar archivo .CSV</button>
          </div>

          <label>Pegar datos desde Excel:
            <textarea id="txt-excel" placeholder="email_o_codigo_estudiante [TAB] nota (0-10) [TAB] observacion (opcional)&#10;juan.perez@fwt.edu.ec	9.50	Excelente desempeño&#10;maria.gomez@fwt.edu.ec	8.00	Buen trabajo"></textarea>
          </label>

          <div class="row end">
            <button id="btn-preview-excel" class="btn primary sm">Validar y Previsualizar</button>
          </div>

          <!-- Preview Table -->
          <div id="preview-container" style="display: none; margin-top: 1rem;">
            <h4>Registros reconocidos para guardar:</h4>
            <div class="table-wrap">
              <table class="table">
                <thead><tr><th>Estudiante</th><th>Nota Reconocida</th><th>Observación</th><th>Estado</th></tr></thead>
                <tbody id="preview-tbody"></tbody>
              </table>
            </div>
            <div class="row end" style="margin-top: 0.75rem;">
              <button id="btn-save-batch" class="btn primary">💾 Confirmar y Guardar Calificaciones</button>
            </div>
          </div>
        </div>
      </section>
    ` : ''}

    <!-- Tabla Principal de Calificaciones -->
    <div class="card">
      <div class="table-wrap">
        <table class="table">
          <thead>
            <tr>
              <th>Código</th>
              <th>Estudiante</th>
              <th>Visibilidad</th>
              <th class="center" style="width: 140px;">Calificación (0-10)</th>
              <th>Observación / Retroalimentación</th>
              ${isTeacherOrAdmin ? `<th class="actions">Acción</th>` : ''}
            </tr>
          </thead>
          <tbody id="grades-tbody">
            <tr><td colspan="${isTeacherOrAdmin ? 6 : 5}" class="center muted">Seleccione los filtros para visualizar calificaciones.</td></tr>
          </tbody>
        </table>
      </div>
    </div>
  `;

  const selLevel = $("#sel-level", root);
  const selSubject = $("#sel-subject", root);
  const selPeriod = $("#sel-period", root);
  const gradesTbody = $("#grades-tbody", root);

  let currentStudents = [];
  let parsedGradesForBatch = [];

  // Inicializar Grados y Períodos
  try {
    const [{ data: levels }, { data: periods }] = await Promise.all([
      sb.from("school_levels").select("*").order("order_index"),
      sb.from("grade_periods").select("*").order("order_index")
    ]);

    (levels || []).forEach(l => selLevel.appendChild(new Option(l.name, l.id)));
    (periods || []).forEach(p => selPeriod.appendChild(new Option(p.name, p.id)));

    await onLevelChanged();
  } catch (err) {
    showError(err);
  }

  async function onLevelChanged() {
    selSubject.innerHTML = `<option value="">Cargando materias...</option>`;
    const { data: subjects } = await sb
      .from("subjects")
      .select("id, name, code")
      .eq("level_id", selLevel.value)
      .order("name");

    selSubject.innerHTML = (subjects && subjects.length)
      ? subjects.map(s => `<option value="${s.id}">${esc(s.code)} - ${esc(s.name)}</option>`).join("")
      : `<option value="">No hay materias en este grado</option>`;
  }

  selLevel.addEventListener("change", onLevelChanged);

  async function loadGrades() {
    if (!selSubject.value || !selPeriod.value) {
      toast("Seleccione una materia y un período", "warn");
      return;
    }

    gradesTbody.innerHTML = `<tr><td colspan="6" class="center muted">Cargando calificaciones...</td></tr>`;

    // 1. Obtener estudiantes del grado
    const { data: students, error: errSt } = await sb
      .from("student_details")
      .select("profile_id, student_code, notes_visibility, profiles(id, full_name, email)")
      .eq("level_id", selLevel.value);

    if (errSt) { showError(errSt); return; }
    currentStudents = students || [];

    // 2. Obtener calificaciones existentes
    const { data: existingGrades, error: errGr } = await sb
      .from("grades")
      .select("*")
      .eq("subject_id", selSubject.value)
      .eq("period_id", selPeriod.value);

    if (errGr) { showError(errGr); return; }

    const gradeMap = new Map();
    (existingGrades || []).forEach(g => gradeMap.set(g.student_id, g));

    if (currentStudents.length === 0) {
      gradesTbody.innerHTML = `<tr><td colspan="6" class="center muted">No hay estudiantes matriculados en este grado.</td></tr>`;
      return;
    }

    gradesTbody.innerHTML = currentStudents.map(st => {
      const g = gradeMap.get(st.profile_id);
      const scoreVal = g ? Number(g.score).toFixed(2) : "";
      const feedbackVal = g ? (g.feedback || "") : "";
      const isPublic = st.notes_visibility === 'public';

      return `
        <tr data-student-id="${st.profile_id}">
          <td><code>${esc(st.student_code || '---')}</code></td>
          <td><strong>${esc(st.profiles?.full_name || st.profiles?.email)}</strong></td>
          <td>
            <span class="badge ${isPublic ? 'ok' : 'warn'}">
              ${isPublic ? '🌐 Pública' : '🔒 Privada'}
            </span>
          </td>
          <td class="center">
            ${isTeacherOrAdmin ? `
              <input type="number" step="0.01" min="0" max="10" class="score-input" value="${scoreVal}" style="width: 90px; text-align: center; font-weight: 700;">
            ` : `
              <strong style="font-size: 1.1rem; color: var(--brand-text);">${scoreVal || '---'}</strong>
            `}
          </td>
          <td>
            ${isTeacherOrAdmin ? `
              <input type="text" class="feedback-input" value="${esc(feedbackVal)}" placeholder="Comentario para el estudiante">
            ` : `
              <span>${esc(feedbackVal) || '<span class="muted hint">Sin comentarios</span>'}</span>
            `}
          </td>
          ${isTeacherOrAdmin ? `
            <td class="actions">
              <button class="btn primary sm btn-save-single" data-student="${st.profile_id}">Guardar</button>
            </td>` : ''}
        </tr>
      `;
    }).join("");

    if (isTeacherOrAdmin) {
      $$(".btn-save-single", gradesTbody).forEach(btn => {
        btn.addEventListener("click", async () => {
          const row = btn.closest("tr");
          const student_id = btn.dataset.student;
          const score = parseFloat(row.querySelector(".score-input").value);
          const feedback = row.querySelector(".feedback-input").value.trim();

          if (isNaN(score) || score < 0 || score > 10) {
            toast("La calificación debe estar entre 0.00 y 10.00", "err");
            return;
          }

          await withBusy(btn, async () => {
            const payload = [{ student_id, subject_id: selSubject.value, period_id: selPeriod.value, score, feedback }];
            const { error } = await sb.rpc("upload_grades_batch", { p_grades: payload });
            if (error) showError(error);
            else toast("Calificación guardada");
          });
        });
      });
    }
  }

  $("#btn-load-grades", root).addEventListener("click", loadGrades);

  // Funciones de Excel masivo
  if (isTeacherOrAdmin) {
    const uploadPanel = $("#upload-panel", root);
    $("#btn-show-upload", root).addEventListener("click", () => {
      uploadPanel.style.display = uploadPanel.style.display === "none" ? "block" : "none";
    });
    $("#btn-close-upload", root).addEventListener("click", () => { uploadPanel.style.display = "none"; });

    // Descargar plantilla CSV con lista de alumnos del curso
    $("#btn-download-template", root).addEventListener("click", async () => {
      if (!currentStudents.length) await loadGrades();
      if (!currentStudents.length) { toast("No hay alumnos en este grado para generar plantilla", "warn"); return; }

      const headers = "Identificador (Email o Codigo),Nombre Estudiante,Nota (0 a 10),Observacion\n";
      const rows = currentStudents.map(s => `"${s.profiles?.email || s.student_code}","${s.profiles?.full_name || ''}",0.00,""`).join("\n");
      const blob = new Blob([headers + rows], { type: "text/csv;charset=utf-8;" });
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = `Plantilla_Notas_${selLevel.options[selLevel.selectedIndex]?.text || 'Grado'}.csv`;
      a.click();
    });

    // Subir archivo CSV
    $("#btn-browse-file", root).addEventListener("click", () => $("#file-csv", root).click());
    $("#file-csv", root).addEventListener("change", (e) => {
      const file = e.target.files[0];
      if (!file) return;
      const reader = new FileReader();
      reader.onload = (ev) => {
        $("#txt-excel", root).value = ev.target.result;
        toast("Archivo cargado en el área de texto");
      };
      reader.readAsText(file);
    });

    // Parsear datos de Excel/CSV
    $("#btn-preview-excel", root).addEventListener("click", async () => {
      const text = $("#txt-excel", root).value.trim();
      if (!text) { toast("Pega datos o carga un archivo primero", "warn"); return; }
      if (!currentStudents.length) await loadGrades();

      const lines = text.split(/\r?\n/);
      parsedGradesForBatch = [];
      const previewTbody = $("#preview-tbody", root);
      previewTbody.innerHTML = "";

      for (let line of lines) {
        line = line.trim();
        if (!line || line.toLowerCase().includes("identificador") || line.toLowerCase().includes("email")) continue;

        // Separar por tab o coma o punto y coma
        const parts = line.split(/[\t;,]/).map(p => p.trim().replace(/^"|"$/g, ''));
        if (parts.length < 2) continue;

        const idOrEmail = parts[0].toLowerCase();
        const score = parseFloat(parts[1].replace(',', '.'));
        const feedback = parts[2] || "";

        // Buscar estudiante
        const match = currentStudents.find(s =>
          (s.profiles?.email && s.profiles.email.toLowerCase() === idOrEmail) ||
          (s.student_code && s.student_code.toLowerCase() === idOrEmail) ||
          (s.profiles?.full_name && s.profiles.full_name.toLowerCase().includes(idOrEmail))
        );

        if (match && !isNaN(score) && score >= 0 && score <= 10) {
          parsedGradesForBatch.push({
            student_id: match.profile_id,
            subject_id: selSubject.value,
            period_id: selPeriod.value,
            score,
            feedback
          });

          previewTbody.innerHTML += `
            <tr>
              <td><strong>${esc(match.profiles?.full_name || idOrEmail)}</strong></td>
              <td><b style="color: var(--brand-text);">${score.toFixed(2)}</b></td>
              <td>${esc(feedback)}</td>
              <td><span class="badge ok">✓ Válido</span></td>
            </tr>
          `;
        } else {
          previewTbody.innerHTML += `
            <tr style="opacity:0.6;">
              <td>${esc(idOrEmail)}</td>
              <td>${isNaN(score) ? 'Inválido' : score}</td>
              <td>${esc(feedback)}</td>
              <td><span class="badge off">✗ No reconocido</span></td>
            </tr>
          `;
        }
      }

      if (parsedGradesForBatch.length > 0) {
        $("#preview-container", root).style.display = "block";
        toast(`Se reconocieron ${parsedGradesForBatch.length} notas válidas.`);
      } else {
        toast("No se pudieron emparejar notas con los estudiantes de este grado", "err");
      }
    });

    // Guardar lote masivo
    $("#btn-save-batch", root).addEventListener("click", async () => {
      if (!parsedGradesForBatch.length) return;
      const btn = $("#btn-save-batch", root);
      await withBusy(btn, async () => {
        const { error } = await sb.rpc("upload_grades_batch", { p_grades: parsedGradesForBatch });
        if (error) showError(error);
        else {
          toast(`¡${parsedGradesForBatch.length} calificaciones guardadas con éxito!`);
          $("#upload-panel", root).style.display = "none";
          $("#preview-container", root).style.display = "none";
          $("#txt-excel", root).value = "";
          await loadGrades();
        }
      });
    });
  }
}

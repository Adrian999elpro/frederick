// Vista: Rankings Académicos FWT (General, por Especialidad Técnica y por Materia Única)
// Exclusivamente para estudiantes con visibilidad de notas pública.
import { sb, $, $$, esc, showError } from "../core.js?v=20261018-community";

export async function render(root) {
  root.innerHTML = `
    <header class="row" style="justify-content: space-between; margin-bottom: 1.25rem;">
      <div>
        <h2 style="color: var(--brand-text); margin: 0;">🏆 Cuadro de Honor y Rankings FWT</h2>
        <p class="muted" style="margin: 4px 0 0;">Rankings institucionales, por especialidad técnica y por materias específicas</p>
      </div>
    </header>

    <!-- Pestañas de Modo de Ranking -->
    <div class="row" style="gap: 8px; margin-bottom: 1.5rem; border-bottom: 2px solid var(--line); padding-bottom: 8px;">
      <button class="btn primary sm tab-btn active" data-tab="tab-specialty">🎓 Por Especialidad Técnica</button>
      <button class="btn ghost sm tab-btn" data-tab="tab-subject">📘 Por Materia Específica</button>
      <button class="btn ghost sm tab-btn" data-tab="tab-general">🌐 General por Grado</button>
    </div>

    <!-- Regla de Privacidad Alert -->
    <div class="callout" style="background: var(--info-bg); color: var(--info); border: 1px solid var(--info-border); margin-bottom: 1.5rem; border-radius: 12px; padding: 0.85rem 1.2rem;">
      ℹ️ <b>Regla de Honor:</b> Siguiendo las directrices de privacidad, en todos los rankings únicamente participan estudiantes que configuraron sus calificaciones como <b>Públicas</b> en su perfil institucional.
    </div>

    <!-- SECCIÓN 1: RANKING POR ESPECIALIDAD TÉCNICA -->
    <section id="tab-specialty" class="ranking-tab-content">
      <div class="card" style="padding: 1rem 1.25rem; margin-bottom: 1.25rem;">
        <div class="row" style="justify-content: space-between; gap: 1rem;">
          <label style="display:flex; align-items:center; gap:8px; font-weight:700;">
            <span>Especialidad Técnica:</span>
            <select id="sel-specialty-filter" style="width: auto; min-width: 250px; font-weight: 600;"></select>
          </label>
          <label style="display:flex; align-items:center; gap:8px;">
            <span>Curso:</span>
            <select id="sel-specialty-level" style="width: auto; min-width: 180px;">
              <option value="">Todo Bachillerato (1ro a 3ro)</option>
            </select>
          </label>
        </div>
      </div>

      <div id="podium-specialty" class="podium-container"></div>

      <div class="card">
        <h3 id="specialty-table-title" style="margin-bottom: 1rem; color: var(--brand-text);">Mejores Estudiantes de la Especialidad</h3>
        <div class="table-wrap">
          <table class="table">
            <thead>
              <tr>
                <th style="width: 70px;" class="center">Puesto</th>
                <th>Estudiante</th>
                <th>Curso</th>
                <th class="center">Materias Evaluadas</th>
                <th class="center" style="width: 140px;">Prom. Técnico</th>
                <th class="center" style="width: 130px;">Prom. General</th>
              </tr>
            </thead>
            <tbody id="specialty-ranking-tbody">
              <tr><td colspan="6" class="center muted">Cargando ranking de especialidad...</td></tr>
            </tbody>
          </table>
        </div>
      </div>
    </section>

    <!-- SECCIÓN 2: RANKING POR MATERIA ESPECÍFICA / ÚNICA -->
    <section id="tab-subject" class="ranking-tab-content" style="display: none;">
      <div class="card" style="padding: 1rem 1.25rem; margin-bottom: 1.25rem;">
        <div class="row" style="gap: 1rem;">
          <label style="flex: 1; min-width: 240px;">Filtrar materias por Especialidad:
            <select id="sel-subject-specialty">
              <option value="">Todas las asignaturas</option>
            </select>
          </label>
          <label style="flex: 1; min-width: 260px;">Seleccionar Materia Específica:
            <select id="sel-specific-subject" style="font-weight: 700; color: var(--brand-text);"></select>
          </label>
        </div>
      </div>

      <div id="podium-subject" class="podium-container"></div>

      <div class="card">
        <h3 id="subject-table-title" style="margin-bottom: 1rem; color: var(--brand-text);">Cuadro de Honor en la Materia</h3>
        <div class="table-wrap">
          <table class="table">
            <thead>
              <tr>
                <th style="width: 70px;" class="center">Puesto</th>
                <th>Estudiante</th>
                <th>Grado / Curso</th>
                <th>Especialidad</th>
                <th class="center" style="width: 140px;">Calificación</th>
                <th>Observación Docente</th>
              </tr>
            </thead>
            <tbody id="subject-ranking-tbody">
              <tr><td colspan="6" class="center muted">Seleccione una materia para ver su ranking.</td></tr>
            </tbody>
          </table>
        </div>
      </div>
    </section>

    <!-- SECCIÓN 3: RANKING GENERAL POR GRADO (8vo a 3ro Bach) -->
    <section id="tab-general" class="ranking-tab-content" style="display: none;">
      <div class="card" style="padding: 1rem 1.25rem; margin-bottom: 1.25rem;">
        <div class="row" style="justify-content: space-between;">
          <label style="display:flex; align-items:center; gap:8px;">
            <span>Filtrar por Grado:</span>
            <select id="sel-general-level" style="width: auto; min-width: 220px;">
              <option value="">Todos los Grados (General)</option>
            </select>
          </label>
        </div>
      </div>

      <div id="podium-general" class="podium-container"></div>

      <div class="card">
        <h3 style="margin-bottom: 1rem;">Tabla General Institucional</h3>
        <div class="table-wrap">
          <table class="table">
            <thead>
              <tr>
                <th style="width: 70px;" class="center">Puesto</th>
                <th>Estudiante</th>
                <th>Grado / Especialidad</th>
                <th class="center">Materias</th>
                <th class="center" style="width: 130px;">Promedio General</th>
              </tr>
            </thead>
            <tbody id="general-ranking-tbody">
              <tr><td colspan="5" class="center muted">Cargando...</td></tr>
            </tbody>
          </table>
        </div>
      </div>
    </section>
  `;

  // Referencias DOM
  const selSpecialtyFilter = $("#sel-specialty-filter", root);
  const selSpecialtyLevel = $("#sel-specialty-level", root);
  const podiumSpecialty = $("#podium-specialty", root);
  const tbodySpecialty = $("#specialty-ranking-tbody", root);

  const selSubjectSpecialty = $("#sel-subject-specialty", root);
  const selSpecificSubject = $("#sel-specific-subject", root);
  const podiumSubject = $("#podium-subject", root);
  const tbodySubject = $("#subject-ranking-tbody", root);

  const selGeneralLevel = $("#sel-general-level", root);
  const podiumGeneral = $("#podium-general", root);
  const tbodyGeneral = $("#general-ranking-tbody", root);

  let specialtiesList = [];
  let levelsList = [];
  let allSubjectsList = [];

  // Pestañas
  $$(".tab-btn", root).forEach(btn => {
    btn.addEventListener("click", () => {
      $$(".tab-btn", root).forEach(b => {
        b.classList.remove("active");
        b.classList.remove("primary");
        b.classList.add("ghost");
      });
      btn.classList.add("active");
      btn.classList.remove("ghost");
      btn.classList.add("primary");

      $$(".ranking-tab-content", root).forEach(c => c.style.display = "none");
      $(`#${btn.dataset.tab}`, root).style.display = "block";
    });
  });

  // Inicializar Datos
  try {
    const [{ data: specs }, { data: levels }, { data: subjects }] = await Promise.all([
      sb.from("technical_specialties").select("*").order("name"),
      sb.from("school_levels").select("*").order("order_index"),
      sb.from("subjects").select("*, technical_specialties(short_name), school_levels(name)").order("name")
    ]);

    specialtiesList = specs || [];
    levelsList = levels || [];
    allSubjectsList = subjects || [];

    // Poblar Especialidades
    specialtiesList.forEach(sp => {
      selSpecialtyFilter.appendChild(new Option(`${sp.name} (${sp.short_name})`, sp.id));
      selSubjectSpecialty.appendChild(new Option(sp.name, sp.id));
    });

    // Poblar Grados
    levelsList.forEach(l => {
      selGeneralLevel.appendChild(new Option(l.name, l.id));
      if (l.code.includes("BACH")) {
        selSpecialtyLevel.appendChild(new Option(l.name, l.id));
      }
    });

    // Poblar Materias
    updateSubjectDropdown();

    await loadSpecialtyRanking();
    await loadSubjectRanking();
    await loadGeneralRanking();
  } catch (err) {
    showError(err);
  }

  // 1. CARGA RANKING POR ESPECIALIDAD TÉCNICA
  async function loadSpecialtyRanking() {
    const specId = selSpecialtyFilter.value;
    if (!specId) return;

    const levelId = selSpecialtyLevel.value || null;
    tbodySpecialty.innerHTML = `<tr><td colspan="6" class="center muted">Actualizando ranking de especialidad...</td></tr>`;
    podiumSpecialty.innerHTML = "";

    const specObj = specialtiesList.find(s => s.id === specId);
    if (specObj) {
      $("#specialty-table-title", root).textContent = `🏆 Cuadro de Honor: Bachillerato Técnico en ${specObj.name}`;
    }

    const { data, error } = await sb.rpc("get_specialty_ranking", {
      p_specialty_id: specId,
      p_level_id: levelId
    });

    if (error) {
      tbodySpecialty.innerHTML = `<tr><td colspan="6" class="center" style="color:var(--danger)">${esc(error.message)}</td></tr>`;
      return;
    }

    if (!data || data.length === 0) {
      tbodySpecialty.innerHTML = `<tr><td colspan="6" class="center muted" style="padding:2.5rem;">No hay estudiantes de esta especialidad con notas públicas aún.</td></tr>`;
      return;
    }

    // Podio Top 3 Especialidad
    const top3 = data.slice(0, 3);
    podiumSpecialty.innerHTML = top3.map((st, idx) => {
      const cls = idx === 0 ? "first" : idx === 1 ? "second" : "third";
      const medal = idx === 0 ? "🥇" : idx === 1 ? "🥈" : "🥉";
      return `
        <div class="podium-card ${cls}">
          <div class="podium-medal">${medal}</div>
          <span class="badge" style="margin-bottom:6px;">${idx + 1}º Lugar</span>
          <h3 style="margin:4px 0 2px;">${esc(st.full_name)}</h3>
          <span class="muted" style="font-size:0.85rem;">${esc(st.level_name)}</span>
          ${st.bio ? `<p class="hint" style="font-style:italic; margin:6px 0;">"${esc(st.bio)}"` : ''}
          <div class="podium-score" style="margin-top:6px;">${Number(st.technical_average).toFixed(2)}</div>
          <span class="hint">Prom. Técnico / 10</span>
        </div>
      `;
    }).join("");

    // Tabla
    tbodySpecialty.innerHTML = data.map((st, i) => {
      const rankNum = i + 1;
      let badgeStyle = "background:var(--line); font-weight:800;";
      if (rankNum === 1) badgeStyle = "background:#f59e0b; color:#2b1700; font-weight:800;";
      else if (rankNum === 2) badgeStyle = "background:#cbd5e1; color:#0f172a; font-weight:800;";
      else if (rankNum === 3) badgeStyle = "background:#b45309; color:#fff; font-weight:800;";

      return `
        <tr>
          <td class="center"><span class="badge" style="${badgeStyle}">#${rankNum}</span></td>
          <td>
            <strong>${esc(st.full_name)}</strong>
            ${st.bio ? `<div class="hint muted" style="font-style:italic;">${esc(st.bio)}</div>` : ''}
          </td>
          <td><span class="badge blue">${esc(st.level_name)}</span></td>
          <td class="center">${st.total_subjects}</td>
          <td class="center">
            <strong style="color: var(--brand-text); font-size:1.15rem;">${Number(st.technical_average).toFixed(2)}</strong>
          </td>
          <td class="center">
            <span class="muted" style="font-weight:600;">${Number(st.average_score).toFixed(2)}</span>
          </td>
        </tr>
      `;
    }).join("");
  }

  // 2. CARGA RANKING POR MATERIA ESPECÍFICA
  function updateSubjectDropdown() {
    selSpecificSubject.innerHTML = "";
    const filterSpecId = selSubjectSpecialty.value;

    const filtered = filterSpecId
      ? allSubjectsList.filter(s => s.specialty_id === filterSpecId)
      : allSubjectsList;

    if (filtered.length === 0) {
      selSpecificSubject.innerHTML = `<option value="">No hay materias registradas</option>`;
      return;
    }

    filtered.forEach(s => {
      const tag = s.technical_specialties?.short_name ? `[${s.technical_specialties.short_name}]` : '[Tronco Común]';
      selSpecificSubject.appendChild(new Option(`${tag} ${s.name} (${s.school_levels?.name || ''})`, s.id));
    });
  }

  async function loadSubjectRanking() {
    const subjectId = selSpecificSubject.value;
    if (!subjectId) {
      tbodySubject.innerHTML = `<tr><td colspan="6" class="center muted">Seleccione una materia específica.</td></tr>`;
      podiumSubject.innerHTML = "";
      return;
    }

    tbodySubject.innerHTML = `<tr><td colspan="6" class="center muted">Consultando mejores estudiantes en esta materia...</td></tr>`;
    podiumSubject.innerHTML = "";

    const subj = allSubjectsList.find(s => s.id === subjectId);
    if (subj) {
      $("#subject-table-title", root).textContent = `📘 Cuadro de Honor: ${subj.name} (${subj.code})`;
    }

    const { data, error } = await sb.rpc("get_subject_ranking", { p_subject_id: subjectId });

    if (error) {
      tbodySubject.innerHTML = `<tr><td colspan="6" class="center" style="color:var(--danger)">${esc(error.message)}</td></tr>`;
      return;
    }

    if (!data || data.length === 0) {
      tbodySubject.innerHTML = `<tr><td colspan="6" class="center muted" style="padding:2.5rem;">No hay notas registradas o públicas para esta asignatura todavía.</td></tr>`;
      return;
    }

    // Podio Top 3 Materia
    const top3 = data.slice(0, 3);
    podiumSubject.innerHTML = top3.map((st, idx) => {
      const cls = idx === 0 ? "first" : idx === 1 ? "second" : "third";
      const medal = idx === 0 ? "🥇" : idx === 1 ? "🥈" : "🥉";
      return `
        <div class="podium-card ${cls}">
          <div class="podium-medal">${medal}</div>
          <span class="badge" style="margin-bottom:6px;">${idx + 1}º Lugar</span>
          <h3 style="margin:4px 0 2px;">${esc(st.full_name)}</h3>
          <span class="muted" style="font-size:0.85rem;">${esc(st.level_name)}</span>
          <span class="badge red" style="margin-top:4px;">${esc(st.specialty_name)}</span>
          <div class="podium-score" style="margin-top:6px;">${Number(st.score).toFixed(2)}</div>
          <span class="hint">Nota / 10.00</span>
        </div>
      `;
    }).join("");

    // Tabla
    tbodySubject.innerHTML = data.map((st, i) => {
      const rankNum = i + 1;
      let badgeStyle = "background:var(--line); font-weight:800;";
      if (rankNum === 1) badgeStyle = "background:#f59e0b; color:#2b1700; font-weight:800;";
      else if (rankNum === 2) badgeStyle = "background:#cbd5e1; color:#0f172a; font-weight:800;";
      else if (rankNum === 3) badgeStyle = "background:#b45309; color:#fff; font-weight:800;";

      return `
        <tr>
          <td class="center"><span class="badge" style="${badgeStyle}">#${rankNum}</span></td>
          <td>
            <strong>${esc(st.full_name)}</strong>
            ${st.bio ? `<div class="hint muted" style="font-style:italic;">${esc(st.bio)}</div>` : ''}
          </td>
          <td><span class="badge blue">${esc(st.level_name)}</span></td>
          <td><span class="badge ${st.is_technical ? 'red' : 'gray'}">${esc(st.specialty_name)}</span></td>
          <td class="center">
            <strong style="color: var(--brand-text); font-size:1.2rem;">${Number(st.score).toFixed(2)}</strong>
            <span class="muted" style="font-size:0.75rem;">/ 10</span>
          </td>
          <td>${st.feedback ? esc(st.feedback) : '<span class="muted hint">---</span>'}</td>
        </tr>
      `;
    }).join("");
  }

  // 3. CARGA RANKING GENERAL
  async function loadGeneralRanking() {
    tbodyGeneral.innerHTML = `<tr><td colspan="5" class="center muted">Actualizando...</td></tr>`;
    podiumGeneral.innerHTML = "";

    const levelId = selGeneralLevel.value || null;
    const { data, error } = await sb.rpc("get_academic_ranking", { p_level_id: levelId });

    if (error || !data || data.length === 0) {
      tbodyGeneral.innerHTML = `<tr><td colspan="5" class="center muted" style="padding:2rem;">No hay registros con notas públicas.</td></tr>`;
      return;
    }

    const top3 = data.slice(0, 3);
    podiumGeneral.innerHTML = top3.map((st, idx) => {
      const cls = idx === 0 ? "first" : idx === 1 ? "second" : "third";
      const medal = idx === 0 ? "🥇" : idx === 1 ? "🥈" : "🥉";
      return `
        <div class="podium-card ${cls}">
          <div class="podium-medal">${medal}</div>
          <span class="badge" style="margin-bottom:6px;">${idx + 1}º Lugar</span>
          <h3 style="margin:4px 0 2px;">${esc(st.full_name)}</h3>
          <span class="muted" style="font-size:0.85rem;">${esc(st.level_name)}</span>
          ${st.specialty_name ? `<span class="badge red" style="margin-top:4px;">🎓 ${esc(st.specialty_name)}</span>` : ''}
          <div class="podium-score" style="margin-top:6px;">${Number(st.average_score).toFixed(2)}</div>
        </div>
      `;
    }).join("");

    tbodyGeneral.innerHTML = data.map((st, i) => `
      <tr>
        <td class="center"><span class="badge" style="font-weight:800;">#${i + 1}</span></td>
        <td><strong>${esc(st.full_name)}</strong></td>
        <td>
          <span class="badge blue">${esc(st.level_name)}</span>
          ${st.specialty_name ? `<span class="badge red">🎓 ${esc(st.specialty_name)}</span>` : ''}
        </td>
        <td class="center">${st.total_subjects}</td>
        <td class="center"><strong style="color: var(--brand-text); font-size:1.15rem;">${Number(st.average_score).toFixed(2)}</strong></td>
      </tr>
    `).join("");
  }

  // Listeners
  selSpecialtyFilter.addEventListener("change", loadSpecialtyRanking);
  selSpecialtyLevel.addEventListener("change", loadSpecialtyRanking);

  selSubjectSpecialty.addEventListener("change", () => {
    updateSubjectDropdown();
    loadSubjectRanking();
  });
  selSpecificSubject.addEventListener("change", loadSubjectRanking);

  selGeneralLevel.addEventListener("change", loadGeneralRanking);
}

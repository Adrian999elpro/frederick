// Shell de la aplicación FWT: navegación por permisos, buscador rápido, inicio y carga diferida de cada sección.
import { CONFIG, requireAccess, can, logout, $, $$, esc, showError } from "./core.js?v=20261018-community";
import { profilePhotoUrl } from "./profile-photo.js?v=20261018-community";
import { setupTerminal } from "./terminal.js?v=20261031-app-admin-card";
import { autoEnhanceSelects, initTheme, routeBar } from "./ui.js?v=20261018-community";

const VIEWS = [
  { id: "forum", title: "💬 Foro del colegio", load: () => import("./views/chat.js?v=20261018-community") },
  { id: "groups", title: "👥 Grupos", load: () => import("./views/chat.js?v=20261018-community") },
  { id: "messages", title: "✉️ Mensajes privados", load: () => import("./views/chat.js?v=20261018-community") },
  { id: "home", title: "🏠 Inicio" },
  { id: "announcements", title: "📢 Novedades",            permission: "announcements.read", load: () => import("./views/announcements.js?v=20261018-community") },
  { id: "ranking",       title: "🏆 Ranking Escolar",       permission: "ranking.read",       load: () => import("./views/ranking.js?v=20261018-community") },
  { id: "grades",        title: "📊 Calificaciones",        permission: "grades.read",        load: () => import("./views/grades.js?v=20261018-community") },
  { id: "subjects",      title: "📚 Materias y Docentes",   permission: "grades.read",        load: () => import("./views/subjects.js?v=20261018-community") },
  { id: "cards",         title: "💳 Tarjetas NFC",          permission: "nfc.manage",         load: () => import("./views/cards.js?v=20261031-app-admin-card") },
  { id: "attendance", title: "📲 Registro de asistencia", load: () => import("./views/attendance.js?v=20261018-community") },
  { id: "council", title: "🗳️ Consejo estudiantil", load: () => import("./views/polls.js?v=20261018-community") },
  { id: "custom-polls", title: "🗳️ Votaciones personalizadas", load: () => import("./views/polls.js?v=20261018-community") },
  { id: "manage-polls", title: "🛠️ Administrar votaciones", permission: "polls.manage", load: () => import("./views/polls.js?v=20261018-community") },
  { id: "applications", title: "📝 Postulaciones", load: () => import("./views/applications.js?v=20261018-community") },
  { id: "card-registration", title: "💳 Registrar tarjetas", permission: "terminal.operate", load: () => import("./views/card-registration.js?v=20261018-community") },
  { id: "kiosk-profile", title: "👤 Consulta con tarjeta", permission: "terminal.operate", load: () => import("./views/kiosk-profile.js?v=20261018-community") },
  { id: "users",         title: "👥 Usuarios",              permission: "users.read",         load: () => import("./views/users.js?v=20261018-community") },
  { id: "roles",         title: "🛡️ Roles y Permisos",     permission: "roles.manage",       load: () => import("./views/roles.js?v=20261018-community") },
  { id: "settings",      title: "⚙️ Ajustes",              permission: "settings.manage",    load: () => import("./views/settings.js?v=20261018-community") },
  { id: "audit",         title: "📜 Auditoría",             permission: "audit.read",         load: () => import("./views/audit.js?v=20261018-community") },
  { id: "terminal-activity", title: "📟 Actividad del terminal", permission: "users.manage", load: () => import("./views/terminal-activity.js?v=20261101-terminal-activity") },
  { id: "profile", title: "🙂 Mi perfil", load: () => import("./views/profile-editor.js?v=20261018-community") },
  { id: "privacy", title: "🔒 Privacidad", load: () => import("./views/privacy.js?v=20261018-community") },
  { id: "security", title: "🔑 Seguridad", load: () => import("./views/security.js?v=20261018-community") },
  { id: "community", title: "🤝 Comunidad", load: () => import("./views/community.js?v=20261018-community") },
  { id: "my-card", title: "🪪 Mi tarjeta y curso", load: () => import("./views/my-card.js?v=20261018-community") },
];

const HELP = {
  forum: "Conversa y comparte fotos con el colegio.", groups: "Crea grupos y participa con tus compañeros.", messages: "Habla en privado con otra persona.",
  attendance: "Registra la asistencia acercando una tarjeta.", council: "Consulta las listas y vota con tu tarjeta.",
  "custom-polls": "Participa en las decisiones del colegio.", "manage-polls": "Define motivos, tiempos y resultados de votaciones.",
  applications: "Presenta tu plan o revisa postulaciones.", "card-registration": "Lee una tarjeta y vincúlala a una cuenta.", "kiosk-profile": "Consulta tus notas con tu tarjeta personal.",
  privacy: "Elige quién ve tu perfil y tus calificaciones.",
  security: "Cambia tu contraseña de acceso.",
  community: "Conoce los perfiles compartidos en el colegio.",
  "my-card": "Completa tus datos y solicita vincular tu tarjeta.",
  profile: "Tu foto, tus datos y las especialidades que te interesan.",
  announcements: "Lee los avisos y las actividades del colegio.",
  grades: "Consulta las notas del año lectivo.",
  subjects: "Encuentra tus materias y docentes.",
  ranking: "Conoce a los estudiantes destacados.",
  cards: "Asigna y revisa las tarjetas del colegio.",
  users: "Gestiona las cuentas de estudiantes y personal.",
  roles: "Define qué puede hacer cada rol.",
  settings: "Configura el acceso a la plataforma.",
  audit: "Revisa los cambios realizados en el sistema.",
  "terminal-activity": "Consulta cuándo se abrió y desbloqueó el terminal escolar.",
};
const GROUPS = [
  ["Conversaciones", ["forum", "groups", "messages"]],
  ["Lo principal", ["attendance", "council", "card-registration", "announcements", "custom-polls"]],
  ["Mi cuenta", ["profile", "privacy", "security", "my-card"]],
  ["Mi colegio", ["grades", "subjects", "ranking", "community", "applications", "kiosk-profile"]],
  ["Administración", ["cards", "manage-polls", "users", "roles", "settings", "audit", "terminal-activity"]],
];
const ROLE_NAMES = { admin: "Administrador", rector: "Rector", estudiante: "Estudiante", docente: "Docente", encargado_consejo: "Encargado del consejo", usuario: "Usuario" };
const FUN_FACTS = [
  "Frederick W. Taylor (1856–1915) fue un ingeniero mecánico estadounidense, conocido como el padre de la administración científica.",
  "En 1911 Taylor publicó «Los principios de la administración científica», uno de los libros más influyentes de la gestión moderna.",
  "Hacia 1900, Taylor y Maunsel White desarrollaron aceros rápidos para herramientas de corte, base de la industria mecánica.",
  "Tu tarjeta NFC es tu llave: sirve para asistencia, votaciones y para ver tu perfil en el terminal del colegio.",
  "Calidad más no cantidad: este es el lema de nuestra unidad educativa.",
];

// El sello va dentro de la web. Si una copia vieja de config.js (en caché) aún apunta a otro sitio, se usa el local.
const LOGO = String(CONFIG.LOGO_URL).startsWith("img/") ? CONFIG.LOGO_URL : "img/sello.png";
const roleLabel = (r) => ROLE_NAMES[r] ?? (String(r || "usuario").replace(/_/g, " ").replace(/^./, (c) => c.toUpperCase()));
const split = (title) => { const i = title.indexOf(" "); return { icon: title.slice(0, i), label: title.slice(i + 1) }; };
const greeting = () => { const h = new Date().getHours(); return h < 12 ? "Buenos días" : h < 19 ? "Buenas tardes" : "Buenas noches"; };

const access = await requireAccess();
if (access) boot(access);


function boot(access) {
  const logoEl = $("[data-logo]"); if (logoEl) logoEl.src = LOGO;
  const shortEl = $("[data-short]"); if (shortEl) shortEl.textContent = CONFIG.APP_SHORT;
  document.title = `${CONFIG.APP_SHORT} · Panel`;
  const setName = (n) => { $("#who").textContent = n; };
  setName(access.full_name || access.email);
  $("#role-label").textContent = roleLabel(access.role);
  $("#logout").addEventListener("click", () => logout());
  initTheme($("#theme-toggle"));
  autoEnhanceSelects();

  async function refreshAvatar() {
    try {
      const url = await profilePhotoUrl(access.id);
      $("#header-avatar").innerHTML = url ? `<img src="${esc(url)}" alt="">` : esc((access.full_name || "?").trim()[0]?.toUpperCase() || "👤");
    } catch { $("#header-avatar").textContent = "👤"; }
  }
  refreshAvatar();
  addEventListener("profile-updated", (e) => {
    if (e.detail?.full_name) { access.full_name = e.detail.full_name; setName(e.detail.full_name); }
    refreshAvatar();
  });

  // Con contraseña temporal solo se permite cambiarla.
  const allowed = VIEWS.filter((v) => access.must_change_password ? v.id === "security" : (!v.permission || can(access, v.permission)));
  const terminal = access.must_change_password ? null : setupTerminal(access);
  const groups = GROUPS.map(([title, ids], gi) => ({ title, gi, views: ids.map((id) => allowed.find((v) => v.id === id)).filter(Boolean) })).filter((g) => g.views.length);
  const groupOf = (id) => groups.find((g) => g.views.some((v) => v.id === id));

  /* ---------- Menú lateral ---------- */
  const navItem = (v, gi) => { const { icon, label } = split(v.title); return `<a href="#${v.id}" data-id="${v.id}" class="nav-item g${gi}"><span class="ni" aria-hidden="true">${icon}</span><span>${esc(label)}</span></a>`; };
  $("#nav").innerHTML =
    (allowed.some((v) => v.id === "home") && !access.must_change_password ? `<a href="#home" data-id="home" class="nav-item g9"><span class="ni" aria-hidden="true">🏠</span><span>Inicio</span></a>` : "") +
    groups.map((g) => `<section class="nav-group"><h2>${esc(g.title)}</h2>${g.views.map((v) => navItem(v, g.gi)).join("")}</section>`).join("");

  const side = $("#side"), scrim = $("#scrim"), toggle = $("#menu-toggle");
  const setDrawer = (open) => {
    side.classList.toggle("open", open); scrim.hidden = !open;
    toggle.setAttribute("aria-expanded", String(open));
    document.body.classList.toggle("no-scroll", open);
  };
  toggle.addEventListener("click", () => setDrawer(!side.classList.contains("open")));
  scrim.addEventListener("click", () => setDrawer(false));
  side.addEventListener("click", (e) => { if (e.target.closest("a")) setDrawer(false); });

  /* ---------- Barra inferior (teléfono) ---------- */
  const has = (id) => allowed.some((v) => v.id === id);
  const second = ["announcements", "forum"].find(has);
  const tab = (id, icon, label) => `<a href="#${id}" data-id="${id}" class="tab"><span class="ti" aria-hidden="true">${icon}</span><span>${label}</span></a>`;
  $("#tabbar").innerHTML = access.must_change_password ? "" :
    tab("home", "🏠", "Inicio") +
    (second ? tab(second, second === "forum" ? "💬" : "📢", second === "forum" ? "Foro" : "Novedades") : "") +
    `<button type="button" class="tab tab-search" id="tab-search" aria-label="Buscar"><span class="ti" aria-hidden="true">🔎</span><span>Buscar</span></button>` +
    (has("profile") ? tab("profile", "🙂", "Perfil") : "") +
    `<button type="button" class="tab" id="tab-more" aria-label="Todas las opciones"><span class="ti" aria-hidden="true">☰</span><span>Más</span></button>`;
  $("#tab-more")?.addEventListener("click", () => setDrawer(true));

  /* ---------- Buscador rápido (Ctrl/⌘ + K) ---------- */
  const entries = [
    ...allowed.filter((v) => v.id !== "home" || !access.must_change_password).map((v) => {
      const { icon, label } = split(v.title);
      return { icon, label, hint: HELP[v.id] || groupOf(v.id)?.title || "", run: () => { location.hash = v.id; } };
    }),
    { icon: "🌗", label: "Cambiar entre tema claro y oscuro", hint: "Apariencia", run: () => $("#theme-toggle").click() },
    { icon: "🚪", label: "Cerrar sesión", hint: "Salir de la plataforma", run: () => logout() },
  ];
  const norm = (s) => String(s).normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
  function openPalette() {
    if ($("#palette")) return;
    const d = document.createElement("dialog");
    d.id = "palette"; d.className = "palette"; d.setAttribute("aria-label", "Buscar o ir a una sección");
    d.innerHTML = `<div class="pal-box"><div class="pal-input"><span aria-hidden="true">🔎</span><input type="search" placeholder="¿A dónde quieres ir? Escribe: notas, votar, tarjeta…" autocomplete="off" aria-label="Buscar"></div><ul class="pal-list" role="listbox"></ul><p class="pal-foot"><kbd>↑</kbd><kbd>↓</kbd> para moverte · <kbd>Enter</kbd> para abrir · <kbd>Esc</kbd> para cerrar</p></div>`;
    const input = $("input", d), list = $(".pal-list", d);
    let shown = [], active = 0;
    const paint = () => {
      const q = norm(input.value.trim());
      shown = entries.filter((e) => !q || norm(`${e.label} ${e.hint}`).includes(q)).slice(0, 12);
      active = Math.min(active, Math.max(0, shown.length - 1));
      list.innerHTML = shown.length
        ? shown.map((e, i) => `<li role="option" data-i="${i}" ${i === active ? 'aria-selected="true"' : ""}><span class="pi" aria-hidden="true">${e.icon}</span><span class="pt"><b>${esc(e.label)}</b><small>${esc(e.hint)}</small></span></li>`).join("")
        : `<li class="pal-empty">No encontré nada con «${esc(input.value)}». Prueba con otra palabra.</li>`;
      list.querySelector('[aria-selected="true"]')?.scrollIntoView({ block: "nearest" });
    };
    const go = (i) => { const e = shown[i]; if (!e) return; d.close(); e.run(); };
    input.addEventListener("input", () => { active = 0; paint(); });
    input.addEventListener("keydown", (ev) => {
      if (ev.key === "ArrowDown") { ev.preventDefault(); active = Math.min(shown.length - 1, active + 1); paint(); }
      else if (ev.key === "ArrowUp") { ev.preventDefault(); active = Math.max(0, active - 1); paint(); }
      else if (ev.key === "Enter") { ev.preventDefault(); go(active); }
    });
    list.addEventListener("click", (ev) => { const li = ev.target.closest("[data-i]"); if (li) go(Number(li.dataset.i)); });
    list.addEventListener("pointermove", (ev) => { const li = ev.target.closest("[data-i]"); if (li && Number(li.dataset.i) !== active) { active = Number(li.dataset.i); paint(); } });
    d.addEventListener("click", (ev) => { if (ev.target === d) d.close(); });
    d.addEventListener("close", () => d.remove());
    document.body.append(d); d.showModal(); paint(); input.focus();
  }
  $("#open-search").addEventListener("click", openPalette);
  $("#tab-search")?.addEventListener("click", openPalette);
  document.addEventListener("keydown", (e) => {
    if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "k") { e.preventDefault(); openPalette(); }
    else if (e.key === "Escape" && side.classList.contains("open")) { setDrawer(false); toggle.focus(); }
  });
  if (access.must_change_password) $("#open-search").hidden = true;

  /* ---------- Inicio ---------- */
  function renderHome(main) {
    const first = esc((access.full_name || "bienvenido").split(" ")[0]);
    const prefer = access.role === "estudiante"
      ? ["announcements", "grades", "ranking", "council", "forum", "my-card"]
      : ["attendance", "announcements", "manage-polls", "council", "users", "cards", "forum"];
    const quick = prefer.filter(has).slice(0, 4).map((id) => allowed.find((v) => v.id === id));
    const fact = FUN_FACTS[Math.floor(Date.now() / 86_400_000) % FUN_FACTS.length];
    const rawDate = new Date().toLocaleDateString("es-EC", { weekday: "long", day: "numeric", month: "long" });
    const date = rawDate.charAt(0).toUpperCase() + rawDate.slice(1);
    const tile = (v, gi, i) => { const { icon, label } = split(v.title); return `<a class="tile g${gi}" href="#${v.id}" style="--i:${i}" data-text="${esc(norm(`${label} ${HELP[v.id] ?? ""}`))}"><span class="tile-icon" aria-hidden="true">${icon}</span><span class="tile-body"><strong>${esc(label)}</strong><span>${esc(HELP[v.id] ?? "")}</span></span><span class="tile-go" aria-hidden="true">→</span></a>`; };
    main.innerHTML = `
      <section class="hero-home">
        <img class="hero-seal" src="${esc(LOGO)}" alt="" width="220" height="220">
        <div class="hero-text">
          <span class="chip">${esc(date)}</span>
          <h1>${greeting()}, ${first} <span class="wave" aria-hidden="true">👋</span></h1>
          <p>¿Qué quieres hacer hoy? Elige una opción o búscala escribiendo.</p>
          <label class="home-search"><span aria-hidden="true">🔎</span><input id="home-filter" type="search" placeholder="Buscar: notas, votar, asistencia…" autocomplete="off" aria-label="Filtrar opciones"></label>
        </div>
      </section>
      ${quick.length ? `<section class="home-section" data-keep><h2>⚡ Lo más usado</h2><div class="quick-grid">${quick.map((v, i) => { const { icon, label } = split(v.title); return `<a class="quick g${groupOf(v.id)?.gi ?? 0}" href="#${v.id}" style="--i:${i}"><span class="qi" aria-hidden="true">${icon}</span><strong>${esc(label)}</strong><small>${esc(HELP[v.id] ?? "")}</small></a>`; }).join("")}</div></section>` : ""}
      <div id="home-groups">${groups.map((g, gi) => `<section class="home-section"><h2>${esc(g.title)}</h2><div class="tile-grid">${g.views.map((v, i) => tile(v, g.gi, gi * 4 + i)).join("")}</div></section>`).join("")}</div>
      <p class="home-empty" id="home-empty" hidden>No encontré opciones con ese texto. Prueba con otra palabra.</p>
      <aside class="fact"><span aria-hidden="true">💡</span><p><b>¿Sabías que…?</b> ${esc(fact)}</p></aside>`;
    const filter = $("#home-filter", main);
    filter.addEventListener("input", () => {
      const q = norm(filter.value.trim());
      let any = false;
      $$(".tile", main).forEach((t) => { const show = !q || t.dataset.text.includes(q); t.hidden = !show; any ||= show; });
      $$("#home-groups .home-section", main).forEach((s) => { s.hidden = !$$(".tile", s).some((t) => !t.hidden); });
      $("[data-keep]", main)?.toggleAttribute("hidden", !!q);
      $("#home-empty", main).hidden = any;
    });
  }

  /* ---------- Rutas ---------- */
  let token = 0;
  async function route() {
    const mine = ++token;
    const requested = location.hash.slice(1).split("/")[0] || "home";
    if (terminal && !terminal.allows(requested)) { location.replace(`#${terminal.fallback()}`); return; }
    const view = allowed.find((v) => v.id === requested) ?? allowed.find((v) => v.id === "home") ?? allowed[0];
    setDrawer(false);
    routeBar();
    const { label } = split(view.title);
    $("#page-title").textContent = label;
    $("#crumb").textContent = view.id === "home" ? CONFIG.APP_SHORT : (groupOf(view.id)?.title ?? CONFIG.APP_SHORT);
    document.title = `${label} · ${CONFIG.APP_SHORT}`;
    $$("#nav .nav-item, #tabbar a.tab").forEach((a) => { if (a.dataset.id === view.id) a.setAttribute("aria-current", "page"); else a.removeAttribute("aria-current"); });
    $("#nav [aria-current]")?.scrollIntoView({ block: "nearest" });
    const main = $("#main");
    window.scrollTo(0, 0);
    if (view.id === "home") { renderHome(main); main.focus({ preventScroll: true }); return; }
    main.innerHTML = `<div class="loading" role="status"><span class="spinner" aria-hidden="true"></span><p>Cargando…</p></div>`;
    try {
      const mod = await view.load();
      if (mine !== token) return;
      const host = document.createElement("div");
      host.className = "view-enter";
      main.replaceChildren(host);
      await mod.render(host, { ...access, terminal: terminal?.active() || false });
      if (mine === token) main.focus({ preventScroll: true });
    } catch (err) {
      if (mine === token) {
        main.innerHTML = `<div class="callout err">No se pudo cargar esta sección. Revisa tu conexión e inténtalo de nuevo.</div>`;
        showError(err);
      }
    }
  }
  addEventListener("hashchange", route);
  route();
}

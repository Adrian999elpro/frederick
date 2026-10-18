// Shell de la aplicación FWT: Navegación por permisos y carga diferida de cada sección.
import { CONFIG, requireAccess, can, logout, $, esc, showError } from "./core.js?v=20261018-community";
import { profilePhotoUrl } from "./profile-photo.js?v=20261018-community";
import { setupTerminal } from "./terminal.js?v=20261018-community";

const VIEWS = [
  { id: "forum", title: "💬 Foro del colegio", load: () => import("./views/chat.js?v=20261018-community") },
  { id: "groups", title: "👥 Grupos", load: () => import("./views/chat.js?v=20261018-community") },
  { id: "messages", title: "✉️ Mensajes privados", load: () => import("./views/chat.js?v=20261018-community") },
  { id: "home", title: "⌂ Inicio" },
  { id: "announcements", title: "📢 Novedades",            permission: "announcements.read", load: () => import("./views/announcements.js?v=20261018-community") },
  { id: "ranking",       title: "🏆 Ranking Escolar",       permission: "ranking.read",       load: () => import("./views/ranking.js?v=20261018-community") },
  { id: "grades",        title: "📊 Calificaciones",        permission: "grades.read",        load: () => import("./views/grades.js?v=20261018-community") },
  { id: "subjects",      title: "📚 Materias y Docentes",   permission: "grades.read",        load: () => import("./views/subjects.js?v=20261018-community") },
  { id: "cards",         title: "💳 Tarjetas NFC",          permission: "nfc.manage",         load: () => import("./views/cards.js?v=20261018-community") },
  { id: "attendance", title: "📲 Registro de asistencia", load: () => import("./views/attendance.js?v=20261018-community") },
  { id: "council", title: "🗳️ Consejo estudiantil", load: () => import("./views/polls.js?v=20261018-community") },
  { id: "custom-polls", title: "📊 Votaciones personalizadas", load: () => import("./views/polls.js?v=20261018-community") },
  { id: "manage-polls", title: "🗳️ Administrar votaciones", permission: "polls.manage", load: () => import("./views/polls.js?v=20261018-community") },
  { id: "applications", title: "📝 Postulaciones", load: () => import("./views/applications.js?v=20261018-community") },
  { id: "card-registration", title: "💳 Registrar tarjetas", permission: "terminal.operate", load: () => import("./views/card-registration.js?v=20261018-community") },
  { id: "kiosk-profile", title: "👤 Consulta con tarjeta", permission: "terminal.operate", load: () => import("./views/kiosk-profile.js?v=20261018-community") },
  { id: "users",         title: "👥 Usuarios",              permission: "users.read",         load: () => import("./views/users.js?v=20261018-community") },
  { id: "roles",         title: "🛡️ Roles y Permisos",     permission: "roles.manage",       load: () => import("./views/roles.js?v=20261018-community") },
  { id: "settings",      title: "⚙️ Ajustes",              permission: "settings.manage",    load: () => import("./views/settings.js?v=20261018-community") },
  { id: "audit",         title: "📜 Auditoría",             permission: "audit.read",         load: () => import("./views/audit.js?v=20261018-community") },
  { id: "profile", title: "👤 Mi perfil", load: () => import("./views/profile-editor.js?v=20261018-community") },
  { id: "privacy", title: "🔒 Privacidad", load: () => import("./views/privacy.js?v=20261018-community") },
  { id: "security", title: "🔑 Seguridad", load: () => import("./views/security.js?v=20261018-community") },
  { id: "community", title: "🤝 Comunidad", load: () => import("./views/community.js?v=20261018-community") },
  { id: "my-card", title: "💳 Mi tarjeta y curso", load: () => import("./views/my-card.js?v=20261018-community") },
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
  vote: "Elige a tus representantes estudiantiles.",
  stats: "Consulta los resultados de las elecciones.",
  cards: "Asigna y revisa las tarjetas del colegio.",
  elections: "Organiza las listas y las votaciones.",
  users: "Gestiona las cuentas de estudiantes y personal.",
  roles: "Define qué puede hacer cada rol.",
  settings: "Configura el acceso a la plataforma.",
  audit: "Revisa los cambios realizados en el sistema."
};
const GROUPS = [
  ["Conversaciones", ["forum", "groups", "messages"]],
  ["Opciones principales", ["attendance", "council", "card-registration", "announcements", "custom-polls"]],
  ["Mi cuenta", ["profile", "privacy", "security", "my-card"]],
  ["Mi colegio", ["grades", "subjects", "ranking", "community", "applications", "kiosk-profile"]],
  ["Administración", ["cards", "manage-polls", "users", "roles", "settings", "audit"]]
];

const access = await requireAccess();
if (access) boot(access);

function boot(access) {
  const logoEl = document.querySelector("[data-logo]");
  if (logoEl) logoEl.src = CONFIG.LOGO_URL;

  const shortEl = document.querySelector("[data-short]");
  if (shortEl) shortEl.textContent = CONFIG.APP_SHORT;

  document.title = `${CONFIG.APP_NAME} · Panel`;
  $("#who").textContent = `${access.full_name || access.email} (${access.role.toUpperCase()})`;
  $("#logout").addEventListener("click", () => logout());
  async function refreshAvatar() {
    try {
      const url = await profilePhotoUrl(access.id);
      $("#header-avatar").innerHTML = url ? `<img src="${esc(url)}" alt="">` : "👤";
    } catch { $("#header-avatar").textContent = "👤"; }
  }
  refreshAvatar();
  addEventListener("profile-updated", e => {
    if (e.detail?.full_name) { access.full_name = e.detail.full_name; $("#who").textContent = e.detail.full_name; }
    refreshAvatar();
  });

  // Con contraseña temporal solo se permite el perfil hasta cambiarla
  const allowed = VIEWS.filter((v) => access.must_change_password ? v.id === "security" : (!v.permission || can(access, v.permission)));
  const terminal = access.must_change_password ? null : setupTerminal(access);
  const groups = GROUPS.map(([title, ids]) => ({ title, views: ids.map(id => allowed.find(v => v.id === id)).filter(Boolean) })).filter(g => g.views.length);
  $("#nav").innerHTML = groups.map(g => `<section><h2>${esc(g.title)}</h2>${g.views.map(v => `<a href="#${v.id}" data-id="${v.id}" class="nav-link">${esc(v.title)}</a>`).join("")}</section>`).join("");
  const toggle = $("#menu-toggle");
  const closeMenu = () => { $("#nav").hidden = true; toggle.setAttribute("aria-expanded", "false"); };
  toggle.addEventListener("click", () => {
    const open = toggle.getAttribute("aria-expanded") !== "true";
    toggle.setAttribute("aria-expanded", String(open)); $("#nav").hidden = !open;
  });
  $("#nav").addEventListener("click", e => { if (e.target.closest("a")) closeMenu(); });
  document.addEventListener("keydown", e => { if (e.key === "Escape" && !$("#nav").hidden) { closeMenu(); toggle.focus(); } });
  if (access.must_change_password) $("[data-shortcut=home]").hidden = true;

  let token = 0;
  async function route() {
    const mine = ++token;
    const requested=location.hash.slice(1).split("/")[0]||"home";
    if(terminal && !terminal.allows(requested)){location.replace(`#${terminal.fallback()}`);return;}
    const view = allowed.find((v) => v.id === requested) ?? allowed[0];
    closeMenu();
    document.querySelectorAll("[data-shortcut]").forEach(a => {
      if (a.dataset.shortcut === view.id) a.setAttribute("aria-current", "page"); else a.removeAttribute("aria-current");
    });
    $("#nav").querySelectorAll("a").forEach((a) => a.toggleAttribute("aria-current", a.dataset.id === view.id));
    $("#nav [aria-current]")?.setAttribute("aria-current", "page");

    const main = $("#main");
    window.scrollTo(0,0);
    if (view.id === "home") {
      main.innerHTML = `<header class="home-welcome"><span class="eyebrow">TU ESPACIO ESCOLAR</span><h1>Hola, ${esc((access.full_name || "bienvenido").split(" ")[0])}</h1><p class="muted">¿Qué necesitas hacer hoy? Elige una opción para empezar.</p></header>${groups.map(g => `<section class="home-section"><h2>${esc(g.title)}</h2><div class="home-grid">${g.views.map(v => `<a class="home-tile" href="#${v.id}"><strong>${esc(v.title)}</strong><span>${esc(HELP[v.id])}</span><span class="tile-open">Abrir →</span></a>`).join("")}</div></section>`).join("")}`;
      main.focus({ preventScroll: true });
      return;
    }
    main.innerHTML = `<div class="card center muted" style="padding: 3rem;"><p>Cargando sección...</p></div>`;

    try {
      const mod = await view.load();
      if (mine !== token) return;
      const host = document.createElement("div");
      main.replaceChildren(host);
      await mod.render(host, { ...access, terminal: terminal?.active() || false });
      if (mine === token) main.focus({ preventScroll: true });
    } catch (err) {
      if (mine === token) {
        main.innerHTML = `<div class="callout err">No se pudo cargar esta sección.</div>`;
        showError(err);
      }
    }
  }

  addEventListener("hashchange", route);
  route();
}

// Shell de la aplicación FWT: Navegación por permisos y carga diferida de cada sección.
import { CONFIG, requireAccess, can, logout, $, esc, showError } from "./core.js";

const VIEWS = [
  { id: "announcements", title: "📢 Novedades",            permission: "announcements.read", load: () => import("./views/announcements.js") },
  { id: "ranking",       title: "🏆 Ranking Escolar",       permission: "ranking.read",       load: () => import("./views/ranking.js") },
  { id: "grades",        title: "📊 Calificaciones",        permission: "grades.read",        load: () => import("./views/grades.js") },
  { id: "subjects",      title: "📚 Materias y Docentes",   permission: "grades.read",        load: () => import("./views/subjects.js") },
  { id: "cards",         title: "💳 Tarjetas NFC",          permission: "nfc.manage",         load: () => import("./views/cards.js") },
  { id: "vote",          title: "🗳️ Votar",                permission: "elections.vote",     load: () => import("./views/vote.js") },
  { id: "stats",         title: "📈 Estadísticas Voto",     permission: "elections.stats",    load: () => import("./views/stats.js") },
  { id: "elections",     title: "🗳️ Gestión Elecciones",   permission: "elections.manage",   load: () => import("./views/elections.js") },
  { id: "users",         title: "👥 Usuarios",              permission: "users.read",         load: () => import("./views/users.js") },
  { id: "roles",         title: "🛡️ Roles y Permisos",     permission: "roles.manage",       load: () => import("./views/roles.js") },
  { id: "settings",      title: "⚙️ Ajustes",              permission: "settings.manage",    load: () => import("./views/settings.js") },
  { id: "audit",         title: "📜 Auditoría",             permission: "audit.read",         load: () => import("./views/audit.js") },
  { id: "profile",       title: "👤 Mi Perfil",                                                load: () => import("./views/profile.js") },
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

  // Con contraseña temporal solo se permite el perfil hasta cambiarla
  const allowed = VIEWS.filter((v) => access.must_change_password ? v.id === "profile" : (!v.permission || can(access, v.permission)));
  $("#nav").innerHTML = allowed.map((v) => `<a href="#${v.id}" data-id="${v.id}" class="nav-link">${esc(v.title)}</a>`).join("");

  let token = 0;
  async function route() {
    const mine = ++token;
    const view = allowed.find((v) => v.id === location.hash.slice(1)) ?? allowed[0];
    $("#nav").querySelectorAll("a").forEach((a) => a.toggleAttribute("aria-current", a.dataset.id === view.id));
    $("#nav [aria-current]")?.setAttribute("aria-current", "page");

    const main = $("#main");
    main.innerHTML = `<div class="card center muted" style="padding: 3rem;"><p>Cargando sección...</p></div>`;

    try {
      const mod = await view.load();
      if (mine !== token) return;
      const host = document.createElement("div");
      main.replaceChildren(host);
      await mod.render(host, access);
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

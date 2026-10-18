// Núcleo del frontend: cliente Supabase, sesión, acceso, caché y utilidades de interfaz.
// Aquí NO se decide ninguna autorización: lo que se oculta en pantalla lo vuelve a exigir el servidor (RLS/RPC).
import { createClient } from "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.45.4/+esm";
import { CONFIG } from "./config.js";

export { CONFIG };
export const sb = createClient(CONFIG.SUPABASE_URL, CONFIG.SUPABASE_ANON_KEY, {
  auth: {
    storage: CONFIG.PERSIST_SESSION ? window.localStorage : window.sessionStorage,
    persistSession: true, autoRefreshToken: true, detectSessionInUrl: true,
  },
});

/* ---------- Utilidades de interfaz ---------- */
export const $ = (sel, root = document) => root.querySelector(sel); export const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];
export const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
export const fmtDate = (s) => new Date(s).toLocaleString("es-EC", { dateStyle: "medium", timeStyle: "short" });
export const initials = (name) => (String(name ?? "").trim()[0] ?? "?").toUpperCase();

export function toast(msg, kind = "ok") {
  const box = $("#toasts"); if (!box) return;
  const t = document.createElement("div");
  t.className = `toast ${kind === "ok" ? "" : "err"}`; t.textContent = msg;
  box.append(t); setTimeout(() => t.remove(), 5000);
}

export function confirmBox(message, okLabel = "Confirmar") {
  return new Promise((resolve) => {
    const d = document.createElement("dialog"); d.className = "dlg";
    d.innerHTML = `<form method="dialog" class="form"><p>${esc(message)}</p><div class="row end">
      <button value="no" class="btn ghost">Cancelar</button><button value="yes" class="btn primary">${esc(okLabel)}</button></div></form>`;
    d.addEventListener("close", () => { resolve(d.returnValue === "yes"); d.remove(); });
    document.body.append(d); d.showModal();
  });
}

export async function withBusy(btn, fn) {
  btn.disabled = true;
  try { return await fn(); } finally { btn.disabled = false; }
}

const MESSAGES = {
  already_voted: "Ya registraste tu voto en esta votación.",
  election_not_open: "Esta votación no está abierta.",
  invalid_list: "La lista seleccionada no es válida.",
  forbidden: "No tienes permiso para esta acción.",
  results_hidden: "Los resultados se publican cuando la votación se cierre.",
  election_locked: "Una votación abierta ya no se puede editar.",
  invalid_transition: "Ese cambio de estado no está permitido.",
  election_closed: "La votación ya está cerrada.",
  admin_locked: "Los permisos del rol administrador no se pueden modificar.",
  cannot_change_self: "No puedes cambiar tu propia cuenta desde aquí.",
  invalid_batch: "Revisa la lista: debe tener entre 1 y 100 líneas.",
};
export function showError(err, fallback = "No se pudo completar la operación.") {
  console.error(err);
  const m = `${err?.message ?? ""}`;
  const hit = Object.keys(MESSAGES).find((k) => m.includes(k));
  toast(hit ? MESSAGES[hit] : (err?.code === "42501" ? MESSAGES.forbidden : fallback), "err");
}

/* ---------- Caché en memoria para datos NO sensibles ---------- */
const mem = new Map();
export async function cached(key, ttlMs, loader) {
  const hit = mem.get(key);
  if (hit && Date.now() - hit.t < ttlMs) return hit.v;
  const v = await loader(); mem.set(key, { t: Date.now(), v }); return v;
}
export const invalidate = (key) => mem.delete(key);

/* ---------- Sesión ---------- */
// Autenticación directa a través del cliente Supabase Auth SDK.
export async function login(email, password) {
  const { data, error } = await sb.auth.signInWithPassword({
    email,
    password,
  });

  if (error) {
    throw new Error(error.message || "Credenciales inválidas o correo no verificado.");
  }

  const access = await getAccess(true);
  if (!access) {
    await sb.auth.signOut();
    throw new Error("Tu cuenta no tiene acceso activo.");
  }

  return data;
}

export async function logout(reason) {
  sessionStorage.removeItem("fwt_access");
  await sb.auth.signOut({ scope: "local" }).catch(() => {});
  location.replace(`index.html${reason ? `?msg=${reason}` : ""}`);
}

// Perfil + rol + permisos en UNA llamada; se cachea unos minutos. El servidor devuelve null si la cuenta está inactiva.
export async function getAccess(force = false) {
  if (!force) {
    try {
      const c = JSON.parse(sessionStorage.getItem("fwt_access"));
      if (c && Date.now() - c.t < CONFIG.ACCESS_TTL_MS) return c.a;
    } catch { /* sin caché */ }
  }
  const { data, error } = await sb.rpc("get_my_access");
  if (error || !data) return null;
  sessionStorage.setItem("fwt_access", JSON.stringify({ t: Date.now(), a: data }));
  return data;
}
export const can = (access, code) => !!access?.permissions?.includes(code);

function startIdleTimer() {
  let last = Date.now();
  const bump = () => { last = Date.now(); };
  ["pointerdown", "keydown", "touchstart", "scroll"].forEach((e) => addEventListener(e, bump, { passive: true }));
  const check = () => { if (Date.now() - last > CONFIG.IDLE_MINUTES * 60_000) logout("idle"); };
  setInterval(check, 15_000);
  document.addEventListener("visibilitychange", () => { if (!document.hidden) check(); });
}

// Guardia de página: exige sesión válida y cuenta activa verificadas por el servidor.
export async function requireAccess() {
  const { data } = await sb.auth.getSession();
  if (!data.session) { location.replace("index.html"); return null; }
  const access = await getAccess(true);
  if (!access) { await logout("disabled"); return null; }
  startIdleTimer();
  sb.auth.onAuthStateChange((ev) => { if (ev === "SIGNED_OUT") location.replace("index.html"); });
  return access;
}

/* ---------- Funciones de servidor y archivos ---------- */
export async function invoke(name, body) {
  const { data, error } = await sb.functions.invoke(name, { body });
  if (error) {
    let detail = {}; try { detail = await error.context.json(); } catch { /* sin detalle */ }
    throw new Error(detail.error || error.message);
  }
  return data;
}

export async function photoUrls(paths) {
  const uniq = [...new Set(paths.filter(Boolean))];
  if (!uniq.length) return {};
  const { data } = await sb.storage.from("election-photos").createSignedUrls(uniq, 3600);   // una sola llamada
  return Object.fromEntries((data ?? []).filter((x) => x.signedUrl).map((x) => [x.path, x.signedUrl]));
}
// Pantalla pública: inicio de sesión, registro, recuperación y restablecimiento de contraseña.
import { sb, CONFIG, $, $$, getAccess, login, withBusy } from "./core.js?v=20261018-community";
import { createPasswordRecovery } from "./password-recovery.js?v=20261018-community";

const VIEWS = ["login", "register", "forgot", "verify", "reset"];
const MSG = {
  idle: ["Tu sesión se cerró por inactividad.", "warn"],
  disabled: ["Tu cuenta no tiene acceso activo.", "err"],
  changed: ["Contraseña actualizada. Inicia sesión con la nueva."],
};
const params = new URLSearchParams(location.search);
const recovering = ["reset", "verify", "forgot"].includes(params.get("view")) || location.hash.includes("type=recovery");
const recovery = createPasswordRecovery({
  auth: sb.auth,
  redirectTo: new URL("index.html?view=reset", location.href).href,
});

// Identidad desde la configuración
$$("[data-logo]").forEach((i) => { i.src = CONFIG.LOGO_URL; });
const nameEl = $("[data-name]");
if (nameEl) nameEl.textContent = CONFIG.APP_NAME.replace(/^Unidad Educativa Técnica Particular\s+/, "");
const taglineEl = $("[data-tagline]");
if (taglineEl) taglineEl.textContent = CONFIG.TAGLINE;
document.title = `Acceso · ${CONFIG.APP_SHORT}`;

function note(text, kind = "") {
  const n = $("#note");
  if (!n) return;
  n.textContent = text;
  n.className = `callout ${kind}`;
  n.hidden = !text;
}
function show(name) {
  VIEWS.forEach((v) => {
    const el = $(`#v-${v}`);
    if (el) el.hidden = v !== name;
  });
  note("");
  $(`#v-${name} input`)?.focus();
}
$$("[data-go]").forEach((a) => a.addEventListener("click", (e) => { e.preventDefault(); show(a.dataset.go); }));

// Instalar antes de esperar a las consultas para no perder la apertura de un enlace.
sb.auth.onAuthStateChange((ev, session) => {
  if (ev === "PASSWORD_RECOVERY") {
    recovery.acceptSession(session);
    show("reset");
  }
  if (ev === "SIGNED_OUT") recovery.acceptSession(null);
});

if (recovering) {
  show(params.get("view") === "verify" ? "verify" : "forgot");
  const { data } = await sb.auth.getSession();
  if (params.get("view") === "reset" && data?.session) {
    recovery.acceptSession(data.session);
    show("reset");
  }
}

if (MSG[params.get("msg")]) note(...MSG[params.get("msg")]);

// ¿Ya hay una sesión válida? Entrar directo (salvo si se está restableciendo la contraseña).
if (!recovering) {
  try {
    const { data } = await sb.auth.getSession();
    if (data?.session && await getAccess(true)) location.replace("app.html");
  } catch (err) {
    console.warn("No active session:", err);
  }
}

// El enlace "Crear una cuenta" solo aparece si el administrador abrió el registro.
try {
  const { data: mode } = await sb.rpc("public_registration_mode");
  const regBtn = $("#to-register");
  if (regBtn) regBtn.hidden = !mode || mode === "closed";
  if (!recovering && params.get("view") === "register" && mode && mode !== "closed") show("register");
} catch (err) {
  console.warn("Registration mode check failed:", err);
}

const same = (f) => f.password.value === f.again.value;

$("#f-login").addEventListener("submit", async (e) => {
  e.preventDefault(); const f = e.currentTarget;
  await withBusy(f.querySelector("[type=submit]"), async () => {
    try {
      await login(f.email.value.trim(), f.password.value);
      if (window.FrederickTerminal && !(await getAccess(true))?.permissions?.includes("terminal.operate")) {
        await sb.auth.signOut({scope:"local"});
        throw new Error("Esta app funciona como terminal del colegio. Debe iniciar sesión un encargado. Para tu cuenta personal, usa la página web.");
      }
      location.replace("app.html");
    }
    catch (err) { note(err.message, "err"); f.password.value = ""; }
  });
});

$("#f-register").addEventListener("submit", async (e) => {
  e.preventDefault(); const f = e.currentTarget;
  if (!same(f)) return note("Las contraseñas no coinciden.", "err");
  await withBusy(f.querySelector("[type=submit]"), async () => {
    const { error } = await sb.auth.signUp({
      email: f.email.value.trim(), password: f.password.value,
      options: { data: { full_name: f.full_name.value.trim() }, emailRedirectTo: new URL("index.html", location.href).href },
    });
    // Mensaje único: no se revela si el correo ya existe ni por qué se rechazó.
    if (error) note("No pudimos completar el registro. Revisa los datos o consulta con el administrador.", "err");
    else { f.reset(); note("Revisa tu correo para confirmar la cuenta."); }
  });
});

$("#f-forgot").addEventListener("submit", async (e) => {
  e.preventDefault(); const f = e.currentTarget;
  await withBusy(f.querySelector("[type=submit]"), async () => {
    try {
      const email = await recovery.requestCode(f.email.value);
      $("#f-verify").elements.email.value = email;
      $("#f-verify").elements.token.value = "";
      show("verify");
      note("Si el correo está registrado, recibirás las instrucciones de recuperación. Revisa también Spam.");
      updateResend();
    } catch (err) { note(err.message, "err"); }
  });
});

const resend = $("#resend-code");
function updateResend() {
  const seconds = recovery.remainingSeconds();
  resend.disabled = seconds > 0;
  resend.textContent = seconds ? `Reenviar correo en ${seconds} s` : "Reenviar correo";
}
setInterval(updateResend, 1000);
resend.addEventListener("click", async () => {
  const f = $("#f-verify");
  if (!f.elements.email.reportValidity()) return;
  await withBusy(resend, async () => {
    try {
      await recovery.requestCode(f.elements.email.value);
      f.elements.token.value = "";
      note("Si el correo está registrado, recibirás nuevas instrucciones de recuperación.");
    } catch (err) { note(err.message, "err"); }
  });
  updateResend();
});

$("#f-verify").addEventListener("submit", async (e) => {
  e.preventDefault(); const f = e.currentTarget;
  await withBusy(f.querySelector("[type=submit]"), async () => {
    try {
      await recovery.verifyCode(f.elements.email.value, f.elements.token.value);
      f.elements.token.value = "";
      history.replaceState(null, "", new URL("index.html?view=reset", location.href));
      show("reset");
      note("Correo verificado. Ya puedes elegir tu nueva contraseña.");
    } catch (err) { note(err.message, "err"); }
  });
});

$("#f-reset").addEventListener("submit", async (e) => {
  e.preventDefault(); const f = e.currentTarget;
  if (!same(f)) return note("Las contraseñas no coinciden.", "err");
  await withBusy(f.querySelector("[type=submit]"), async () => {
    try {
      await recovery.changePassword(f.password.value, f.again.value);
      f.reset();
      sessionStorage.removeItem("fwt_access");
      location.replace("index.html?msg=changed");
    } catch (err) { note(err.message, "err"); }
  });
});

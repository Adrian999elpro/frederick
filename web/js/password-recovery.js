// Supabase genera, caduca y verifica los códigos. Nunca se guardan en el navegador.
export function createPasswordRecovery({ auth, redirectTo, now = Date.now }) {
  let ready = false;
  let sending = false;
  let nextSendAt = 0;
  const emailValue = (value) => String(value ?? "").trim().toLowerCase();
  const validEmail = (value) => value.length <= 254 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
  const remainingSeconds = () => Math.max(0, Math.ceil((nextSendAt - now()) / 1000));

  return {
    remainingSeconds,
    acceptSession(session) { ready = !!session?.access_token; },
    async requestCode(value) {
      const email = emailValue(value);
      if (!validEmail(email)) throw new Error("Escribe un correo electrónico válido.");
      if (sending || remainingSeconds()) throw new Error("Espera un minuto antes de solicitar otro correo.");
      ready = false;
      sending = true;
      try {
        const { error } = await auth.resetPasswordForEmail(email, { redirectTo });
        if (error) {
          if (error.status === 429) nextSendAt = now() + 60_000;
          throw new Error(error.status === 429
            ? "Demasiadas solicitudes. Espera un momento antes de intentarlo otra vez."
            : "No pudimos enviar el correo. Inténtalo más tarde o contacta con el colegio.");
        }
        nextSendAt = now() + 60_000;
        return email;
      } finally { sending = false; }
    },
    async verifyCode(emailInput, codeInput) {
      ready = false;
      const email = emailValue(emailInput);
      const token = String(codeInput ?? "").replace(/\s/g, "");
      if (!validEmail(email) || !/^[0-9]{6,10}$/.test(token)) {
        throw new Error("Revisa el correo y escribe el código completo que recibiste.");
      }
      const { data, error } = await auth.verifyOtp({ email, token, type: "recovery" });
      if (error || !data?.session?.access_token) {
        throw new Error("El código no es válido o ya caducó. Revisa el correo o solicita uno nuevo.");
      }
      ready = true;
    },
    async changePassword(password, confirmation) {
      if (!ready) throw new Error("Primero verifica el código o abre el enlace de recuperación de tu correo.");
      if (password !== confirmation) throw new Error("Las contraseñas no coinciden.");
      if (typeof password !== "string" || password.length < 10 || password.length > 128) {
        throw new Error("La contraseña debe tener entre 10 y 128 caracteres.");
      }
      const { error } = await auth.updateUser({ password });
      if (error) throw new Error("No se pudo guardar la contraseña. Revisa los requisitos o solicita otro correo.");
      ready = false;
      await auth.signOut({ scope: "local" });
    },
  };
}

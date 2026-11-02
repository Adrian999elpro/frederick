# Instrucciones para ChatGPT — registro de tarjetas y activación de cuentas (2 de noviembre)

Claude ya escribió y probó localmente (PostgreSQL 16) todo el cambio. Tu trabajo es **publicarlo** y verificarlo en producción. No reescribas la lógica; si algo falla, dime el error exacto.

## Qué cambia
- La web **ya no lee NFC**. Tarjetas solo se registran/asignan/reemplazan en la **app del terminal** y **solo por administradores** (permiso nuevo `cards.register`, solo rol `admin`).
- Nadie escribe ya directamente en `nfc_cards` (se quitó la política `nfc_cards_manage` y el INSERT/UPDATE/DELETE para `authenticated`). Se retiraron `save_nfc_card_binding`, `submit_enrollment` y `review_enrollment` del acceso de usuarios.
- Registro de persona nueva (en el terminal): tarjeta + nombre (+ curso). Se crea una **cuenta pendiente** (correo provisional, contraseña aleatoria que nadie conoce).
- La persona acerca su tarjeta al terminal y pide su **código de activación** (8 caracteres, **24 horas**, un solo uso; si pide otro, el anterior deja de servir; solo mientras no tenga correo vinculado).
- En la web (`index.html` → «Primera vez: activar mi cuenta») escribe código + correo + contraseña. La cuenta queda ligada a su nombre y tarjeta. No hay lista pública de nombres.
- Web «Tarjetas NFC»: directorio de solo lectura (todas las personas, con o sin tarjeta, pendientes, bloqueadas) y botón Bloquear/Desbloquear para administradores.

## Pasos (en este orden)
1. **Prueba primero** en una base de pruebas (nunca en producción): `tests/card-registration.integration.sql` debe terminar con `NOTICE: card-registration: todas las comprobaciones pasaron`. También deben seguir pasando `tests/terminal-scan.integration.sql` y `tests/polls-terminal.integration.sql` (esta última tenía un fallo previo de `submit_council_application`, no relacionado).
2. Aplica las migraciones pendientes en este orden: `20261101121500_terminal_scan.sql`, `20261101121600_terminal_activity.sql`, `20261102000100_card_registration_and_activation.sql`, `20261102000200_terminal_admin_pin.sql` (esta última es el PIN; pruébala como paso aparte). Antes revisa en producción cuáles ya están aplicadas.
3. Despliega las Edge Functions:
   - `terminal-register-card` (con verificación de JWT; ya está en `supabase/config.toml`).
   - `activate-account` con `--no-verify-jwt` (es pública; limita 10 fallos por IP cada 15 min).
   - `_shared/util.ts` cambió (nueva función `requireCheck`): redespliega también `admin-users` y `auth-login`.
4. Si Supabase rechaza el correo provisional `pendiente-xxxx@pendiente.frederick.invalid`, define el secreto `PENDING_EMAIL_DOMAIN` con un dominio que acepte y vuelve a desplegar `terminal-register-card`.
5. Revisa el SMTP de Supabase: el correo integrado tiene un límite muy bajo por hora; para la recuperación de contraseña de todo el colegio conviene un SMTP propio.
6. Publica la web (`web/`) en GitHub Pages. Archivos modificados: `index.html`, `app.html`, `css/redesign.css`, `js/app.js`, `js/auth-page.js`, `js/views/cards.js`, `js/views/polls.js`, `js/views/users.js`, `js/views/profile-editor.js`, `js/views/terminal-activity.js`. Archivos **eliminados** (bórralos del repo): `js/terminal.js`, `js/nfc-reader.js`, `js/views/attendance.js`, `js/views/card-registration.js`, `js/views/kiosk-profile.js`, `js/views/my-card.js`.
7. Prueba de punta a punta con el APK (necesita compilarse; ver `CONTEXTO_APK_PARA_CHATGPT.md`): administrador registra una persona de prueba → la persona acerca su tarjeta y pide el código → lo usa en la web → inicia sesión → desde el panel web aparece «Activa» → el administrador la bloquea y deja de leerse en el terminal.

## Reglas
- No muestres ni guardes códigos de activación en texto plano (solo se guarda el hash SHA-256).
- No cambies la duración (24 h) ni el formato del código sin avisarme.
- Un UID NFC no es un secreto; el único punto fuerte es la sesión administrativa del terminal.
- Entrégame al terminar: qué migraciones se aplicaron, qué funciones se desplegaron, el resultado de las pruebas y cualquier error literal.

## PIN de la tarjeta de administrador (migración `20261102000200_terminal_admin_pin.sql`)
- La tarjeta de administrador sola ya no basta: se necesita tarjeta + PIN de 6 dígitos para abrir el panel del terminal, desbloquear la app y registrar/asignar tarjetas.
- El PIN se guarda con bcrypt (`extensions.crypt`, requiere `pgcrypto`; la migración hace `create extension if not exists pgcrypto with schema extensions`). 5 fallos bloquean 15 minutos. Se restablece desde la web (Seguridad → «Restablecer mi PIN», función `reset_terminal_pin`).
- Una verificación correcta abre una «sesión de administrador» de 10 minutos que se renueva con cada acción. El servidor la exige en `terminal_assign_card`, `terminal_search_people` y en la Edge Function `terminal-register-card` (función `operator_admin_session`). `consume_terminal_unlock` y `log_terminal_event` solo aceptan tickets con `pin_ok = true`.
- `terminal_scan` ahora devuelve `pin_set` y `pin_ok` en las tarjetas de administrador y sigue registrando el evento `admin_card`.
- Pruebas: `tests/card-registration.integration.sql` (incluye PIN, bloqueo y reinicio) y `tests/terminal-scan.integration.sql` deben pasar. `tests/polls-terminal.integration.sql` conserva su fallo previo y ajeno de `submit_council_application`.
- Redespliega `terminal-register-card` (cambió para exigir la sesión).
- Si en producción `pgcrypto` ya vive en otro esquema (no `extensions`), avísame antes de seguir: hay que ajustar `extensions.crypt/gen_salt`.

## Primera tarjeta de administrador
El usuario todavía no tiene tarjetas físicas. Cuando las tenga: iniciar sesión en el terminal con la cuenta administrativa → aparece «Registrar mi tarjeta de administrador» (usa `register_initial_admin_card`, ya existente) → acercar la tarjeta → volver a acercarla para crear el PIN → modo «Registrar tarjetas». No cambies ese flujo.

# Enviar los correos de Frederick con una cuenta de Gmail (SMTP)

Sirve para el correo de recuperación de contraseña. (La activación de cuenta con código **no envía correo**.)
`DESPLIEGUE.md` indica que el SMTP de Gmail ya pudo estar guardado en Supabase: **revisa primero** si ya está activo antes de repetirlo.

## Pasos (los haces tú, en tu cuenta; no se los des a nadie)
1. Cuenta de Google → **Seguridad** → activa la **verificación en 2 pasos**.
2. Entra a https://myaccount.google.com/apppasswords → crea una contraseña de aplicación llamada «Supabase Frederick». Google muestra **16 letras una sola vez**: cópiala sin espacios.
3. Supabase → tu proyecto → **Authentication → Emails → SMTP Settings** (en algunas versiones: *Project Settings → Authentication*) → activa **Enable custom SMTP**:
   - Sender email: tu Gmail (Gmail reescribe cualquier otro remitente).
   - Sender name: `Colegio FWT`
   - Host: `smtp.gmail.com`
   - Port: `465` (SSL) — alternativa `587`.
   - Username: tu Gmail completo.
   - Password: la contraseña de aplicación de 16 letras.
   - Guarda.
4. **Authentication → Rate Limits**: sube el límite de correos por hora si es bajo (con SMTP propio ya no aplica el límite de 2 por hora del servicio integrado).
5. **Authentication → Emails → Reset password**: pega el contenido de `supabase/templates/recovery.html` (debe incluir `{{ .Token }}`; la web verifica ese código).
6. Prueba: en la web pulsa «¿Olvidaste tu contraseña?» con un correo de prueba y revisa también **Spam**.

## Cuidados
- Nunca pegues la contraseña de aplicación en chats, GitHub ni en archivos del proyecto: solo en el panel de Supabase. Si se filtra, revócala en myaccount.google.com/apppasswords y crea otra.
- Gmail personal permite unos 500 correos al día; para un colegio alcanza para recuperaciones, pero los mensajes pueden caer en Spam. Lo ideal a futuro es una cuenta de Gmail/Workspace propia del colegio o un servicio de envío (Resend, Brevo).

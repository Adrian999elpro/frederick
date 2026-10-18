# Correo de recuperación FWT

Plantilla: `recovery.html`. Asunto: `Tu código para recuperar tu cuenta · Frederick`.

Supabase genera el código dinámico `{{ .Token }}`. La web lo verifica con `verifyOtp` de tipo `recovery` antes de permitir una contraseña nueva. No se incluye ningún código real en el repositorio.

En el proyecto alojado, configurar SMTP y copiar la plantilla en Authentication → Emails → Reset password. El archivo local no modifica automáticamente el proyecto remoto.

Remitente temporal autorizado: `adrianvillagomez47@gmail.com`, nombre `Frederick · Plataforma Escolar`.

Para Gmail: host `smtp.gmail.com`, puerto `465`, usuario igual al correo remitente y contraseña de aplicación de Google. Introducir la contraseña únicamente en el panel de Supabase. No guardarla en código, Git ni documentación.

Si más adelante se usa Resend, verificar primero un dominio bajo control del titular. La configuración SMTP de Resend usa `smtp.resend.com`, puerto `465` y usuario `resend`; su clave se introduce solo en el servidor.

La dirección principal de la aplicación y los destinos de recuperación deben apuntar a `https://adrian999elpro.github.io/frederick/` y `https://adrian999elpro.github.io/frederick/index.html?view=reset`.

La entrega real y el uso de un código de correo deben validarse después de configurar el remitente. Las pruebas automáticas usan un servicio simulado y no envían correos ni cambian cuentas reales.

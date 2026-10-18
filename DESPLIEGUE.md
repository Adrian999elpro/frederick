# Estado de despliegue

Proyecto Supabase: Frederick (`kskzurpimoggbzuvwzts`).

Repositorio: https://github.com/Adrian999elpro/frederick

Web publicada: https://adrian999elpro.github.io/frederick/

Publicación de GitHub Actions verificada con resultado satisfactorio.

Las 21 tablas públicas ya existían y tenían RLS habilitado. No se reinstala el esquema ni se modifican cuentas existentes.

Las funciones `admin-users` y `auth-login` se desplegaron con autorización explícita. La primera requiere JWT y valida `users.manage`; la segunda valida credenciales dentro del servidor.

La migración `hosting_access_hardening` está preparada. Su aplicación y verificación se registrarán aquí al concluir el despliegue.

## Verificaciones realizadas

- Sintaxis de los módulos JavaScript del panel sin errores.
- Página de acceso publicada y recursos visuales cargados.
- El panel `app.html` redirige al acceso cuando no hay sesión.
- La API responde a `public_registration_mode` con HTTP 200.
- `admin-users` rechaza la llamada sin credenciales con HTTP 403.
- `auth-login` rechaza credenciales ausentes con HTTP 401.
- No se han creado usuarios de prueba ni modificado notas, asistencia o votos.

## Recuperación por correo

Se añadió verificación de códigos de recuperación con Supabase (`type: recovery`), reenvío con espera de un minuto y cambio de contraseña tras verificar la sesión. Se mantienen compatibles los enlaces de recuperación anteriores.

La plantilla de marca está en `supabase/templates/recovery.html` y el remitente temporal autorizado es `adrianvillagomez47@gmail.com`. La configuración SMTP de Gmail fue guardada por el titular en Supabase; su contraseña de aplicación se introduce exclusivamente en ese panel. La plantilla remota se administra en Authentication → Emails → Reset password; no basta con subir el archivo a GitHub.

Se configuraron la URL principal de GitHub Pages y los dos destinos exactos para confirmación (`index.html`) y recuperación (`index.html?view=reset`). La plantilla personalizada se guardó en Supabase y se verificó tras recargar el panel. La publicación de la pantalla de código terminó correctamente en GitHub Actions. El titular decidió realizar la prueba de correo después; no se ha validado todavía la entrega de Gmail ni se han cambiado contraseñas reales.

Verificaciones de esta mejora: seis pruebas automatizadas del flujo con un servicio simulado, revisión de sintaxis y revisión visual de la pantalla y el correo. No se enviaron mensajes ni se cambiaron contraseñas reales en esas pruebas.

## Mantenimiento del servicio

- GitHub Pages publica únicamente la carpeta `web/` mediante el flujo de Actions.
- Los secretos de servidor permanecen en Supabase.
- El historial remoto inicial estaba vacío: reconciliar el esquema manual y las versiones antes de usar `supabase db push`.
- Mantener los destinos de Supabase Auth al cambiar la dirección definitiva de la web.
- Probar con cuentas de cada rol antes de cargar registros escolares reales.

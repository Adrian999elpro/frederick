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

## Mantenimiento

- GitHub Pages publica únicamente la carpeta `web/` mediante el flujo de Actions.
- Los secretos de servidor permanecen en Supabase.
- El historial remoto inicial estaba vacío: reconciliar el esquema manual y las versiones antes de usar `supabase db push`.
- Configurar destinos de correo en Supabase Auth para la URL definitiva de la web.
- Probar con cuentas de cada rol antes de cargar registros escolares reales.

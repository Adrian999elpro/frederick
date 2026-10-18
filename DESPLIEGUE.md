# Estado de despliegue

Proyecto Supabase: Frederick (`kskzurpimoggbzuvwzts`).

Las 21 tablas públicas ya existían y tenían RLS habilitado. No se reinstala el esquema ni se modifican cuentas existentes.

Las funciones `admin-users` y `auth-login` se desplegaron con autorización explícita. La primera requiere JWT y valida `users.manage`; la segunda valida credenciales dentro del servidor.

La migración `hosting_access_hardening` está preparada. Su aplicación y verificación se registrarán aquí al concluir el despliegue.

## Mantenimiento

- GitHub Pages publica únicamente la carpeta `web/` mediante el flujo de Actions.
- Los secretos de servidor permanecen en Supabase.
- El historial remoto inicial estaba vacío: reconciliar el esquema manual y las versiones antes de usar `supabase db push`.
- Configurar destinos de correo en Supabase Auth para la URL definitiva de la web.
- Probar con cuentas de cada rol antes de cargar registros escolares reales.

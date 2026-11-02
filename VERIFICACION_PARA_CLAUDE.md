# Paquete para revisión de Claude

## Objetivo
Revisar los cambios de Frederick en la web y Supabase indicados en `INSTRUCCIONES_SUPABASE_WEB_PARA_CHATGPT.md`.

## Cambios incluidos
- `supabase/migrations/20261101121500_terminal_scan.sql`: unifica lectura de tarjeta, conserva el dueño de la tarjeta en el ticket y comparte el armado del perfil.
- `supabase/migrations/20261101121600_terminal_activity.sql`: crea el registro privado de actividad y sus RPC; únicamente `users.manage` puede consultar el historial.
- `web/js/views/terminal-activity.js` y `web/js/app.js`: agrega la vista administrativa.
- `tests/terminal-scan.integration.sql`: prueba permisos, privacidad, tickets, eventos y consulta del historial.

## Alcance del APK
El código Flutter proviene sin cambios del ZIP fuente del 1 de noviembre. El instructivo pidió dejar Flutter intacto para que el propietario adapte la app después.

## Estado de validación
La sintaxis de los módulos JavaScript se revisó correctamente. La prueba SQL aún no se ejecutó: este proyecto está en el plan gratuito, que no permite crear una rama de Supabase, y el entorno local no tiene Docker. Por esa razón no se aplicaron las migraciones a producción. Ejecutar `tests/terminal-scan.integration.sql` contra una base de prueba y revisar ambas migraciones antes de aplicarlas a Frederick.

## Firmas nuevas
- `public.terminal_profile_payload(p_profile_id uuid) returns jsonb` (interna, sin permiso de ejecución para usuarios de la API).
- `public.terminal_scan(p_card_uid text) returns jsonb`.
- `public.log_terminal_event(p_ticket uuid, p_event text, p_detail jsonb default '{}'::jsonb) returns void`.
- `public.list_terminal_events(p_limit integer default 100) returns table(event_id bigint, created_at timestamptz, operator_name text, operator_email text, actor_name text, event text, detail jsonb)`.

`authorize_terminal_card(text)`, `terminal_student_profile(text)` y `consume_terminal_unlock(uuid)` se reemplazan manteniendo sus contratos existentes.

# Análisis del proyecto FWT

Revisión: 18 de octubre de 2026. Carpeta original: `Music`.

## Qué hace

El panel web utiliza HTML, CSS y módulos JavaScript sin compilación. Se conecta directamente a Supabase Auth, PostgreSQL, Storage y funciones de servidor. Los menús cambian según los permisos del usuario, pero la autorización efectiva debe cumplirse en la base de datos.

- Usuarios, roles, permisos, perfiles y auditoría.
- Grados desde octavo de EGB hasta tercero de bachillerato y cuatro especialidades técnicas.
- Materias, docentes, períodos y calificaciones; la importación de Excel utiliza archivos CSV, no lectura nativa de XLSX.
- Anuncios institucionales y rankings generales, por materia y por especialidad.
- Elecciones, listas, fotos, voto único, voto en blanco y resultados.
- Registro de tarjetas NFC y asistencia diaria; el lector físico depende de la aplicación Android.

`supabase/functions/admin-users` administra cuentas usando una credencial de servidor y comprueba sesión y permiso `users.manage`. `auth-login` valida credenciales y limita intentos por correo/IP. La web actualmente usa el inicio de sesión directo de Supabase; el módulo móvil usa `auth-login`.

## Estado encontrado en Supabase

El proyecto **Frederick**, referencia `kskzurpimoggbzuvwzts`, ya existía y estaba activo en la región `us-east-1`. Había 21 tablas públicas con RLS habilitado, seis niveles escolares, cuatro especialidades, 16 materias y una cuenta administradora activa. No había historial de migraciones ni Edge Functions desplegadas al comenzar la revisión.

El esquema proviene de una instalación manual y contiene diferencias respecto de las migraciones individuales. Por eso no se debe ejecutar `db push` ni volver a instalar todo sobre Frederick sin reconciliar antes su historial.

## Hallazgos y correcciones preparadas

1. Los privilegios de tabla permitían actualizar todas las columnas del perfil propio, incluido `role_id`, a pesar de la política de filas. La migración nueva restringe la edición pública a nombre y teléfono.
2. Varias funciones internas heredaban ejecución para usuarios anónimos. Se restauran los permisos previstos en las migraciones originales.
3. Faltaban políticas para gestionar roles, listas electorales y asignaciones docentes. Se reponen con comprobación del permiso correspondiente.
4. El bucket `election-photos` era público. La corrección lo vuelve privado; el frontend ya utiliza enlaces firmados.
5. Los scripts consolidados históricos pueden promover usuarios existentes a administradores. Se conservan en la carpeta original y se excluyen del repositorio; no se ejecutan durante este despliegue.
6. Se incorpora publicación automática de `web/` en GitHub Pages. El SDK completo de Flutter, cachés y configuraciones locales se excluyen de GitHub.

La migración revisada está en `supabase/migrations/20261018062607_hosting_access_hardening.sql`. Su aplicación depende de autorización específica; el estado final se documenta en `DESPLIEGUE.md`.

## Límites de esta revisión

El código Android no está listo para distribuir como APK: `flutter/fwt_auth` contiene el módulo real y una entrada de ejemplo, pero `flutter/fwt_auth/wft` todavía es la demostración del contador de Flutter. El ejemplo conserva marcadores de URL/clave y no tiene proyecto ejecutable independiente. Publicar la web no compila ni conecta automáticamente esa app.

No se ha realizado una auditoría exhaustiva ni una prueba completa con usuarios docentes/estudiantes, notas o votos reales. No se conoce la contraseña de la cuenta existente; las verificaciones públicas y de permisos no sustituyen las pruebas funcionales autenticadas. El uso de UID NFC identifica tarjetas, pero no prueba resistencia a su clonación.

Los rankings públicos y los anuncios tienen acceso público previsto por el código original. Antes de cargar datos escolares reales, la institución debe decidir qué información quiere publicar y validar los permisos de cada rol.

# Frederick · Plataforma escolar FWT

Panel web institucional con Supabase y módulo Android para NFC.

- Repositorio: https://github.com/Adrian999elpro/frederick
- Web prevista: https://adrian999elpro.github.io/frederick/
- Proyecto Supabase existente: Frederick (`kskzurpimoggbzuvwzts`)

## Funciones

Usuarios y permisos, materias y docentes, notas con importación CSV, anuncios, rankings, elecciones y registro de tarjetas NFC. La asistencia con lector NFC se implementa en el módulo Android.

## Estructura

- `web/`: sitio estático que se publica completo en GitHub Pages.
- `supabase/migrations/`: esquema y cambios de seguridad.
- `supabase/functions/`: inicio de sesión y administración de usuarios en el servidor.
- `supabase/tests/`: pruebas SQL de desarrollo; nunca ejecutarlas en producción.
- `flutter/fwt_auth/`: módulo móvil y ejemplo; consultar sus límites en `ANALISIS.md`.
- `ANALISIS.md`: explicación del código y hallazgos.
- `DESPLIEGUE.md`: estado y mantenimiento del despliegue.

## Ejecutar la web localmente

Desde la raíz: `python -m http.server 8000 --directory web`. Abrir http://localhost:8000.

La configuración pública de Supabase está en `web/js/config.js`. La clave publishable es pública por diseño. Nunca colocar claves secretas o service_role en el navegador o en el repositorio.

## Publicación

En GitHub, Settings → Pages → Source: GitHub Actions. El flujo `.github/workflows/pages.yml` publica solo `web/` al cambiar `main`. La base de datos y las funciones se alojan en Supabase, no en GitHub Pages.

En Supabase Authentication → URL Configuration, añadir la URL real de la web a los destinos autorizados de confirmación y recuperación de contraseña. Conservar los destinos de otras aplicaciones que estén en uso.

## Base de datos

Frederick ya contenía el esquema antes de esta importación. No volver a ejecutar los scripts de instalación ni `supabase db push` sobre ese proyecto: su historial inicial no estaba registrado. Revisar `DESPLIEGUE.md` antes de cualquier migración.

Para una instalación nueva, revisar y aplicar las migraciones individuales en orden. La primera cuenta administradora se provisiona por un operador de confianza; no se incluye una contraseña predeterminada.

## Android

El módulo móvil se conserva como código fuente. El proyecto `wft` aún contiene la aplicación de demostración de Flutter; no es un APK funcional del sistema escolar. Es necesario integrar el ejemplo con el proyecto Android, configurar credenciales públicas y validar el lector en un dispositivo físico.

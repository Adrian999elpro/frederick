# Validación de perfiles, comunidad, consejo y terminal

Comprobaciones realizadas el 18 de octubre de 2026:

- Sintaxis de todos los módulos JavaScript y seis pruebas de recuperación de contraseña: correctas. No se enviaron correos de prueba ni se cambiaron contraseñas reales.
- `tests/profile-privacy.integration.sql`: perfiles privados, notas, fotos, bloqueo de cambios de rol, control administrativo de privacidad y aprobación de tarjeta. Correcto.
- `tests/polls-terminal.integration.sql`: convocatorias inicialmente cerradas, permisos de apertura/revisión, rechazo con motivo, lectura antes del voto, tickets de un uso, prevención de votos duplicados, resultados secretos/identificados y autorización del terminal por tarjeta. Correcto.
- `tests/community.integration.sql`: chats y fotos privados inaccesibles a terceros y moderadores; grupos accesibles a sus miembros y moderación; suspensión temporal, permanente y retirada; perfiles privados y registro de datos del estudiante. Correcto.
- Los tres ensayos de base de datos usan cuentas sintéticas y transacciones que revierten todos sus cambios. No crean conversaciones, votos ni cuentas persistentes.
- Interfaz revisada con datos sintéticos aislados: menú, permisos por rol, mensajes, enlace a perfil privado, botón Enviar mensaje y diseño a 390 píxeles. Estos ensayos no enviaron mensajes a personas reales.
- Flutter: análisis y dos pruebas de navegación correctos. Compilación Android completa publicada en `android-preview-2`.

## Pendiente de comprobar en el teléfono real

Lectura de las tarjetas físicas, compatibilidad del NFC, fijación/desfijación de pantalla y selector de fotografías. El APK necesita internet. En teléfonos personales la fijación de Android puede ser retirada por el propietario.

## Acceso a conversaciones

El permiso `community.moderate` incluye foros y grupos; no incluye lectura de conversaciones directas ajenas. Las fotos se guardan en un contenedor privado y los enlaces de lectura caducan en 60 segundos. Esto es control de acceso de la plataforma, no cifrado de extremo a extremo frente al propietario técnico de la base de datos.

Las tablas internas de mensajes, participantes y tickets no se pueden leer directamente mediante la API. Las funciones revisadas comprueban sesión, estado y acceso antes de devolver datos o escribir. Por ello el asesor de Supabase informa de tablas con RLS sin políticas y funciones privilegiadas: son accesos deliberados a través de funciones verificadas, no tablas públicas. El canje del token aleatorio del terminal admite llamadas sin sesión, pero exige un token emitido tras una tarjeta autorizada, de un solo uso y válido por 60 segundos.

El asesor también conserva advertencias del código anterior, incluyendo funciones antiguas expuestas y protección de contraseñas filtradas desactivada. No se aplicó la migración histórica amplia `20261018062607_hosting_access_hardening.sql`. Este documento no certifica una auditoría completa de los módulos anteriores.

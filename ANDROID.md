# Frederick Escolar para Android

Frederick Escolar es una app Android nativa pensada como terminal del colegio: solo una cuenta administrativa inicia sesión; después, estudiantes y docentes acercan su tarjeta NFC y ven su perfil, su promedio y sus notas sin iniciar sesión; el perfil queda abierto hasta que la persona lo cierre. El mismo teléfono sirve para asistencia, votaciones, registro de tarjetas y anuncios. Tiene modo claro, oscuro o del sistema. La comunidad (foro, grupos y mensajes privados con fotos) y las postulaciones al consejo también están en la app. La administración y la moderación siguen en la web por ahora.

El APK de prueba se descarga desde las publicaciones de GitHub. Abre la versión más reciente en https://github.com/Adrian999elpro/frederick/releases y descarga `Frederick-Escolar.apk`. Android puede pedir permiso para instalar desde el navegador. La aplicación requiere internet y un teléfono con NFC para leer tarjetas.

## Preparar el teléfono del colegio

1. En la web, asigna al encargado un rol con «Usar terminal escolar», los permisos de los modos que atenderá y «Desbloquear terminal».
2. Vincula una tarjeta activa a una cuenta con «Desbloquear terminal», desde Tarjetas NFC. Guarda esta tarjeta con el encargado.
3. Instala el APK e inicia sesión **una sola vez** con el correo de la cuenta administrativa. La sesión se mantiene. Acepta la fijación de pantalla de Android. Esa cuenta necesita también los permisos de votaciones (`polls.manage`, `polls.operate`, `council.open`), porque las acciones del panel se ejecutan con su sesión.
4. El teléfono arranca en «Acerca tu tarjeta». **La tarjeta decide quién es quién**: si es de un administrador (rol con «Desbloquear terminal») se abre el panel del encargado; si es de un estudiante o docente se abre su perfil.
5. En el panel, el administrador elige el modo del terminal (perfil, anuncios, asistencia, votación, registro de tarjetas), crea votaciones, las abre o cierra, abre o cierra las postulaciones del consejo, ve resultados, fija una votación en el terminal y puede desbloquear la app. **El modo y la votación fijados no cambian hasta que un administrador los cambie con su tarjeta** y se conservan aunque se reinicie la app; se borran al cerrar la sesión.
6. El perfil de un estudiante o docente **queda abierto hasta que lo cierre** («Cerrar mi perfil»). Mientras está abierto, otra tarjeta no lo reemplaza; solo la tarjeta de un administrador lo puede cerrar. En votaciones, cada turno requiere leer la tarjeta y termina después de votar o a los 90 segundos.

Nota de privacidad: como el perfil no se oculta solo, si alguien se aleja sin cerrarlo sus notas siguen visibles hasta que alguien lo cierre.

En un teléfono personal Android permite al propietario salir de la fijación usando los controles del sistema y su bloqueo de pantalla. No es un bloqueo absoluto de otras aplicaciones. El propietario puede desinstalar la app y pasar a otro teléfono. El bloqueo completo requiere configurar Android como dispositivo administrado; esta versión no configura ni toma control permanente del teléfono.

## Cuentas, postulaciones y votos

El estudiante puede registrarse en la web con su correo, confirmar el correo y completar «Mi tarjeta y curso». En el modo de registro del terminal puede leer la tarjeta, escribir sus datos y crear su cuenta. La asociación se activa solo después de la confirmación del correo y revisión del colegio.

Las convocatorias del consejo empiezan cerradas. «Abrir postulaciones» y «Revisar postulaciones» son permisos separados. Las listas aprobadas se convierten en opciones de la elección. El rechazo requiere un motivo visible para quien postuló.

Cada votación exige motivo y duración. Al abrirla se fija el padrón de estudiantes activos. Un estudiante puede emitir un voto. La no participación se cuenta por separado, como sin voto/nulo por no participación. En voto secreto no se guarda la identidad junto a la opción. En voto identificado, los resultados finales muestran nombre y elección.

## Firma propia para actualizar sin desinstalar

Mientras no exista un keystore propio, cada APK se firma con una clave de prueba distinta y Android pide desinstalar antes de instalar el siguiente. Para evitarlo, genera un keystore una sola vez (`keytool -genkeypair -v -keystore fwt.jks -alias fwt -keyalg RSA -keysize 2048 -validity 10000`), guárdalo en un lugar seguro y crea estos secretos en GitHub (Settings → Secrets and variables → Actions): `FWT_KEYSTORE_BASE64` (el archivo en base64), `FWT_KEYSTORE_PASSWORD`, `FWT_KEY_ALIAS` y `FWT_KEY_PASSWORD`. El flujo de Android los usa automáticamente. No subas el keystore ni las contraseñas al repositorio.

## Límites de esta versión de prueba

- La app es nativa, pero aún no tiene administración ni herramientas de moderación; para eso usa la web.
- El sello del colegio se descarga de la web del colegio; si no carga, se muestra un ícono.
- La compilación y las pruebas automáticas no sustituyen probar NFC, fijación y fotos en el teléfono real.
- Las tarjetas se reconocen por su identificador NFC; esto no es una autenticación criptográfica anticlonación. El colegio debe controlar la entrega y desactivación de tarjetas.
- Usa la firma de prueba de Android. Una compilación posterior puede requerir desinstalar la anterior. Los datos escolares permanecen en Supabase.
- Para cambiar de equipo, cierra la sesión o desinstala la app del equipo anterior e inicia sesión en el nuevo. El encargado administra las tarjetas desde la web.


## Registro de tarjetas y activación de cuentas (2 de noviembre)
1. Aplica `supabase/migrations/20261102000100_card_registration_and_activation.sql` (después de las dos del 1 de noviembre).
2. Despliega las Edge Functions nuevas: `supabase functions deploy terminal-register-card` y `supabase functions deploy activate-account --no-verify-jwt`. Opcional: secreto `PENDING_EMAIL_DOMAIN` (por defecto `pendiente.frederick.invalid`; si Supabase rechaza ese dominio, usa uno que acepte).
3. Para que el correo de recuperación de contraseña funcione con muchos usuarios configura un SMTP propio en Supabase (el correo integrado tiene un límite muy bajo por hora).
4. En el terminal, un administrador abre el modo «Registrar tarjetas». Las personas piden su código acercando su tarjeta y pulsando «Activar mi acceso a la web».

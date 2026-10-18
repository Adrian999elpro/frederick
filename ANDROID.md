# Frederick Escolar para Android

El APK de prueba se descarga desde las publicaciones de GitHub. Abre la versión más reciente en https://github.com/Adrian999elpro/frederick/releases y descarga `Frederick-Escolar.apk`. Android puede pedir permiso para instalar desde el navegador. La aplicación requiere internet y un teléfono con NFC para leer tarjetas.

## Preparar el teléfono del colegio

1. En la web, asigna al encargado un rol con «Usar terminal escolar», los permisos de los modos que atenderá y «Desbloquear terminal».
2. Vincula una tarjeta activa a una cuenta con «Desbloquear terminal», desde Tarjetas NFC. Guarda esta tarjeta con el encargado.
3. Instala el APK e inicia sesión con la cuenta encargada. Acepta la fijación de pantalla de Android. El teléfono empieza en Anuncios y consulta de perfiles.
4. Acerca la tarjeta del encargado para seleccionar asistencia, consejo, registro de tarjetas, anuncios/perfiles o votaciones personalizadas. Esa misma tarjeta permite desbloquear la aplicación.
5. En consulta, el estudiante acerca su tarjeta y ve sus notas y perfil durante 60 segundos. En votaciones, cada turno requiere otra lectura y termina después de votar o a los 90 segundos.

En un teléfono personal Android permite al propietario salir de la fijación usando los controles del sistema y su bloqueo de pantalla. No es un bloqueo absoluto de otras aplicaciones. El propietario puede desinstalar la app y pasar a otro teléfono. El bloqueo completo requiere configurar Android como dispositivo administrado; esta versión no configura ni toma control permanente del teléfono.

## Cuentas, postulaciones y votos

El estudiante puede registrarse en la web con su correo, confirmar el correo y completar «Mi tarjeta y curso». En el modo de registro del terminal puede leer la tarjeta, escribir sus datos y crear su cuenta. La asociación se activa solo después de la confirmación del correo y revisión del colegio.

Las convocatorias del consejo empiezan cerradas. «Abrir postulaciones» y «Revisar postulaciones» son permisos separados. Las listas aprobadas se convierten en opciones de la elección. El rechazo requiere un motivo visible para quien postuló.

Cada votación exige motivo y duración. Al abrirla se fija el padrón de estudiantes activos. Un estudiante puede emitir un voto. La no participación se cuenta por separado, como sin voto/nulo por no participación. En voto secreto no se guarda la identidad junto a la opción. En voto identificado, los resultados finales muestran nombre y elección.

## Límites de esta versión de prueba

- El APK usa la misma web publicada, con lectura NFC y selección de fotos nativas.
- La compilación y las pruebas automáticas no sustituyen probar NFC, fijación y fotos en el teléfono real.
- Las tarjetas se reconocen por su identificador NFC; esto no es una autenticación criptográfica anticlonación. El colegio debe controlar la entrega y desactivación de tarjetas.
- Usa la firma de prueba de Android. Una compilación posterior puede requerir desinstalar la anterior. Los datos escolares permanecen en Supabase.
- Para cambiar de equipo, cierra la sesión o desinstala la app del equipo anterior e inicia sesión en el nuevo. El encargado administra las tarjetas desde la web.

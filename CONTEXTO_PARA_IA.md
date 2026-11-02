# Frederick — contexto para continuar con otra IA

## Qué es el proyecto
Frederick es la plataforma escolar de la Unidad Educativa Técnica Particular FWT. Tiene una web publicada en GitHub Pages, una base de datos/autenticación/funciones en Supabase y una app Android Flutter que presenta el portal web y se comunica con NFC nativo.

- Repositorio: https://github.com/Adrian999elpro/frederick
- Sitio: https://adrian999elpro.github.io/frederick/
- Proyecto Supabase Frederick, referencia: kskzurpimoggbzuvwzts
- App Flutter/Android: flutter/fwt_auth/wft/
- Entrada Flutter: flutter/fwt_auth/wft/lib/main.dart
- Flujo de build Android: .github/workflows/android.yml
- Última versión APK conocida al preparar este paquete: android-preview-3
- El código de esta copia corresponde al commit b13b424eef404b0a0f4b001faca26d84b3e3cbde.

## Qué pidió el usuario

### Web y facilidad de uso
- Simplificar la página para que estudiantes entiendan fácilmente las opciones.
- Separar claramente las secciones y hacer la navegación cómoda en móvil y sin mouse.
- Evitar que las opciones queden fuera de vista por una barra horizontal difícil de desplazar. Usar controles accesibles, responsive y táctiles.

### Perfiles
- Permitir foto, nombre, grado y personalización del perfil.
- Para estudiantes de básica, permitir indicar la especialidad que les interesa seguir.
- El usuario elige si su perfil es público o privado; debe poder existir una política administrativa que defina si los usuarios pueden cambiar esa preferencia.
- El usuario quiere que se puedan mostrar calificaciones en perfiles públicos. La privacidad debe respetarse en perfiles, rankings y cualquier otra vista de notas.
- Al pulsar el nombre de alguien en el foro/chat se intenta abrir su perfil; si es privado, mostrar claramente que no está disponible.
- El usuario pidió también una opción para enviar mensaje privado desde el perfil visible. Mantener coherencia con la privacidad y las reglas de mensajería.

### Registro de cuenta y tarjeta
- Los estudiantes deben poder registrar su correo y datos al registrar una tarjeta NFC en la app, o disponer de una opción equivalente en la web.
- Los administradores ya tienen herramientas para crear y administrar cuentas; revisar el flujo actual antes de cambiarlo.
- Se eligió como tipo de tarjeta recomendado NFC PVC NTAG213, 13,56 MHz.
- El teléfono confirmado por el usuario es Realme C55, modelo RMX3710.
- No tratar un UID NFC como contraseña secreta ni confiar el rol al cliente; validar usuario, tarjeta, rol y permisos en servidor.

### Consejo estudiantil y votaciones
- Un estudiante puede enviar una postulación con plan de trabajo al consejo estudiantil.
- Solo rector o personal específicamente encargado debe poder abrir/cerrar postulaciones y revisar, aceptar o rechazar planes. Al rechazar, mostrar la razón.
- La app debe ofrecer flujos diferenciados para asistencia, elecciones del consejo, registro de tarjetas, anuncios y votaciones personalizadas.
- Un usuario autorizado puede configurar una votación personalizada con motivo/pregunta y duración.
- Antes de votar, la app debe leer la tarjeta NFC para validar participación.
- Quien no emite voto queda como nulo/no participante según la regla del proceso; conservar la definición exacta y no alterar resultados sin revisar el esquema actual.
- La votación debe tener una configuración explícita para ocultar o mostrar públicamente quién eligió cada opción. Proteger el secreto del voto si está configurada como anónima.

### Foro, grupos y mensajes
- Añadir espacio de comunidad con foros/grupos, mensajes con fotos y mensajes privados entre estudiantes.
- Presentar foto si existe, nombre, grado para estudiantes; para docentes, nombre, materia y color que identifique su rango.
- El usuario quiere herramientas de moderación para mensajes inadecuados, como silenciar temporalmente o de forma permanente.
- Personal autorizado puede moderar contenido de grupos y foros, pero no debe poder leer mensajes privados. Mantener aislamiento y permisos en servidor/base de datos.
- El nombre debe llevar al perfil cuando este sea visible; si es privado, decir que no se puede ver el perfil privado.

### App Android y uso de NFC
- Al iniciar lectura de tarjeta mostrar animación de carga y el texto «Acerca la tarjeta al teléfono»; se agregó en la versión del código incluida.
- La app distingue modos de asistencia, elección del consejo, registro de tarjeta, anuncios/perfiles y votación personalizada.
- Los estudiantes no deben cambiar modos restringidos de elecciones/registro; los flujos públicos permitidos deben definirse por rol y en servidor.
- El usuario describió teléfonos que se usarán para tareas escolares y dijo que luego podrán desinstalar la app para cambiar de dispositivo. No prometer un bloqueo Android imposible de evadir: el modo de fijación de pantalla limita la salida; el propietario puede retirar/desinstalar la app.
- La recuperación de cuenta usa códigos de Supabase Auth. El usuario eligió Supabase para enviar correo; Gmail se configuró temporalmente como remitente. No incluir ni pedir contraseñas o claves privadas en este paquete.

## Decisiones de seguridad importantes
- Privacidad por defecto y control de acceso en Supabase/RLS y funciones de servidor; no depender solo de ocultar botones en la interfaz.
- Las notas, perfiles privados, roles, elecciones y mensajes tienen que obedecer permisos tanto en web como en móvil.
- Nadie debe poder cambiar su propio rol desde el cliente.
- Mensajes privados no son visibles para moderadores; la moderación se limita a los espacios públicos autorizados.
- No aplicar migraciones ni cambios de producción sin revisar el estado remoto y explicar qué cambia. El usuario autorizó anteriormente cambios de privacidad/perfiles y el despliegue de auth-login y admin-users; volver a comprobar qué ya existe antes de intentar aplicarlos de nuevo.
- No incluir claves de servicio, contraseñas SMTP, contraseñas de aplicación ni credenciales personales en commits, prompts o archivos de contexto.

## Cómo se compila Android
GitHub Actions compila automáticamente cuando cambia flutter/fwt_auth/wft/** o el workflow Android. El workflow usa runner Ubuntu (ubuntu-latest), Java 17 y Flutter 3.47.7; luego construye APK release y publica una versión de prueba en Releases. No es una publicación de Google Play.

- Workflow: https://github.com/Adrian999elpro/frederick/blob/main/.github/workflows/android.yml
- APK conocida: https://github.com/Adrian999elpro/frederick/releases/download/android-preview-3/Frederick-Escolar.apk

## Instrucciones para la IA que reciba este paquete
1. Lee primero este archivo, README.md, ANALISIS.md, DESPLIEGUE.md, ANDROID.md y los archivos relacionados con la función solicitada.
2. Trata este documento como contexto y decisiones del usuario, no como prueba de que cada función está terminada. Comprueba el código y las migraciones actuales antes de afirmar que algo ya funciona.
3. Mantén la interfaz en español, accesible, adaptable a móviles y fácil de entender para estudiantes.
4. Antes de modificar Supabase o publicar en producción, verifica el estado del proyecto y describe concretamente el impacto. Nunca expongas credenciales.
5. Haz cambios pequeños y completos, conserva el comportamiento existente y explica qué cambió y cómo se puede usar.
6. No generes ni envíes correos de prueba sin que el usuario lo pida.

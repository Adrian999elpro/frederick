# Frederick Escolar — contexto para que otra IA deje compilando el APK

## Tu tarea
Deja compilando y funcionando la app Android nativa **Frederick Escolar** (Flutter) y entrega el APK. El código ya está escrito, pero **nunca se ha compilado**: quien lo escribió no tenía el SDK de Flutter. Lo más probable es que haya algunos errores de compilación o de análisis que debes encontrar y corregir.

Si no puedes ejecutar Flutter en tu entorno, no inventes que compila. Revisa el código, corrige lo que encuentres y explica qué quedó sin comprobar. El APK real se compila en GitHub Actions (`.github/workflows/android.yml`), que descarga Flutter 3.47.7 con Java 17.

## Qué es el proyecto
Plataforma escolar de la Unidad Educativa Técnica Particular Frederick Winslow Taylor (FWT):
- Web (HTML/JS sin compilación) en GitHub Pages: `https://adrian999elpro.github.io/frederick/`
- Backend: Supabase (Auth, PostgreSQL con RLS, Storage, Edge Functions). Referencia del proyecto: `kskzurpimoggbzuvwzts`.
- App Android en `flutter/fwt_auth/wft/`. **Antes** era un WebView que mostraba la web. **Ahora** es una app 100 % nativa con diseño propio.
- Repositorio: `https://github.com/Adrian999elpro/frederick`

Idioma de toda la interfaz: español. Usuarios: estudiantes de 8.º de EGB a 3.º de bachillerato, docentes, personal. Teléfono de pruebas: Realme C55 (RMX3710). Tarjetas: NFC PVC NTAG213.

## Flujo de uso (decisión del usuario, 1 de noviembre)
- **El inicio de sesión es solo para la cuenta administrativa** que activa el teléfono del colegio. Si inicia sesión una cuenta sin el permiso `terminal.operate`, la app muestra "Esta cuenta no puede usar este teléfono" y ofrece cerrar sesión.
- El teléfono es un **terminal fijo**: se inicia sesión **una sola vez con el correo de una cuenta administrativa** y la sesión se mantiene (almacén seguro). Desde ahí **la tarjeta NFC decide quién es quién**: el terminal lee tarjetas de forma continua y, por cada una, llama **una sola vez** a `terminal_scan`, que responde `{kind:'admin', ticket, name}` (la tarjeta es de un rol con `terminal.unlock`; se abre su panel) o `{kind:'person', profile}` (estudiante o docente; se abre su perfil, completado con `school_person_card`).
- **El perfil de un estudiante/docente queda abierto hasta que lo cierre** (botón «Cerrar mi perfil» o botón Atrás). No hay temporizador. Mientras un perfil está abierto, otra tarjeta no lo reemplaza; solo la tarjeta de un administrador puede cerrarlo.
- **Panel del administrador** (`terminal/admin_panel.dart`, se abre con su tarjeta o con el botón «Encargado»): elegir el modo del terminal (perfil, anuncios, asistencia, votación, registro de tarjetas), **crear votaciones** (`create_school_poll`), abrir/cerrar (`change_school_poll_status`), abrir/cerrar postulaciones del consejo (`set_council_applications_open`), ver resultados (`school_poll_results`), **fijar una votación en el terminal** y **desbloquear la app** (`consume_terminal_unlock` con un permiso de 60 s de un solo uso, ver `terminal_shell.dart`). Cada acción del panel se anota con `log_terminal_event` (el desbloqueo y la lectura de la tarjeta de administrador las registra el servidor); la web las muestra en «Actividad del terminal» (`list_terminal_events`, permiso `users.manage`).
- **El modo y la votación fijados no cambian hasta que un administrador los cambie con su tarjeta**; se guardan en `shared_preferences` (`core/terminal_prefs.dart`) y se borran solo al cerrar la sesión (`Api.signOut`). Las acciones de votaciones se ejecutan con la sesión administrativa del teléfono, por lo que **esa cuenta necesita los permisos** `polls.manage`, `polls.operate` y `council.open`; la tarjeta solo autoriza abrir el panel. Si faltan, el panel muestra el error del servidor.
- Al desbloquear aparece una pantalla con «Volver al terminal», «Abrir mi cuenta» y «Cerrar sesión».
- Consecuencia: las funciones personales (Carnet, Votar, Comunidad, Postulaciones) existen en el código pero solo las ve la cuenta administrativa si abre "Mi cuenta"; los estudiantes no las alcanzan porque no pueden iniciar sesión. Votar con tarjeta se hace en los modos del terminal. No se puede ofrecer mensajería ni postulaciones por tarjeta sin nuevas funciones de servidor (`auth.uid()` es necesario); no las inventes ni apliques migraciones.

## Diseño pedido por el usuario
- No debe parecerse a la página web: pantallas propias, barra de navegación inferior, botones grandes, animaciones suaves.
- Paleta existente: negro `#0E1117`, rojo `#A81717`, rojo oscuro `#7A1313`, rojo vivo `#E00E0E`, dorado `#F59E0B`.
- Modo oscuro elegible por la persona: claro, oscuro o sistema (Perfil → Apariencia).
- Mantener el logo del colegio: `https://www.frederickwinslowtaylor.com/Imagenes/sello.png` (se carga por red; si falla, se muestra un ícono).
- Primera versión: **estudiante y terminal escolar**. La administración queda para después y sigue en la web.

## Estructura de la app (`flutter/fwt_auth/wft/`)
```
lib/main.dart                 Arranque, tema, cambio entre login y app
lib/core/config.dart          URL y clave publishable de Supabase, textos, logo
lib/core/theme.dart           Paleta (clase Fwt), temas claro/oscuro
lib/core/theme_controller.dart Guarda claro/oscuro/sistema (shared_preferences)
lib/core/api.dart             Cliente Supabase, sesión segura, Access, fotos, cambio de contraseña
lib/core/errors.dart          friendlyError(), normalizeUid(), isValidUid()
lib/core/nfc.dart             MethodChannel 'ec.frederick.escolar/nfc' (scan, cancel, pin, unpin)
lib/widgets/common.dart       Avatar, HeroHeader, AsyncView, hoja de lectura NFC animada, confirm, snack
lib/screens/                  login, session_gate, shell (pestañas), home, announcements, card, ranking,
                              vote, profile, grades
lib/community/                Comunidad: person.dart, community_screen.dart (Foro/Grupos/Privados),
                              chat_room_screen.dart (mensajes, fotos, actualización cada 10 s), profile_view_screen.dart
lib/screens/applications_screen.dart  Postulaciones al consejo estudiantil
lib/terminal/terminal_shell.dart    Marco del terminal: modo fijado, detección de tarjeta de administrador
lib/terminal/terminal_context.dart  TerminalCtx y TerminalMode (lo que recibe cada modo)
lib/terminal/card_waiting.dart      Lectura NFC continua (CardLoopMixin, CardWaiting)
lib/terminal/admin_panel.dart       Panel del administrador: modos, votaciones, resultados, desbloqueo
lib/terminal/modes.dart             Modos: perfil, anuncios, asistencia, registro, votación por turno
lib/core/terminal_prefs.dart        Modo y votación fijados (se conservan hasta cerrar sesión)
android/app/src/main/kotlin/com/example/wft/MainActivity.kt   Lector NFC y fijación de pantalla
android/app/build.gradle.kts  Firma (variables FWT_KEYSTORE_*), applicationId ec.frederick.escolar
test/core_test.dart           Pruebas de UID, errores, Access y tema
```
Modos del terminal: Mi perfil con tarjeta (principal, lectura continua), Anuncios, Asistencia, Consejo estudiantil, Registrar tarjetas, Votaciones. Pestañas de "Mi cuenta" (solo administrador): estudiante = Inicio, Comunidad, Carnet, Votar, Perfil (Ranking y Mis notas se abren desde Inicio; Postulaciones desde Votar). Otros roles = Inicio, Comunidad, Ranking, Anuncios, Perfil. `SessionGate` decide: sin sesión → login; sin `terminal.operate` → bloqueo; con permiso → terminal.

## Dependencias (pubspec.yaml)
`supabase_flutter ^2.8.0`, `flutter_secure_storage ^9.2.2`, `shared_preferences ^2.3.0`, `image_picker ^1.1.2`; dev: `flutter_test`, `flutter_lints ^6.0.0`. SDK `^3.13.5`. No hay `pubspec.lock`: se genera con `flutter pub get`.

## Lo que probablemente falle al compilar (revisa primero)
Escrito sin compilador. Puntos a verificar contra las versiones reales de los paquetes:
1. `RadioGroup<String>` (vote_screen.dart, profile_screen.dart, modes.dart). Existe en Flutter recientes; si no, usar `RadioListTile` con `groupValue`/`onChanged`.
2. `DropdownButtonFormField(initialValue: ...)` (card_screen, profile_screen, ranking_screen, modes). Si no existe en la versión, usar `value:`.
3. `CardThemeData` en `ThemeData(cardTheme: ...)` y `Color.withValues(alpha:)` (theme.dart y varios).
4. `SupabaseClient(url, key, authOptions: const AuthClientOptions(autoRefreshToken: false))` y `client.dispose()` en `RegistrationMode` (modes.dart).
5. `SecureLocalStorage extends LocalStorage` con los parámetros `initialize`, `hasAccessToken`, `accessToken`, `removePersistedSession`, `persistSession` (core/api.dart). Si la API cambió, adaptar o usar el almacenamiento por defecto.
6. `SearchOptions` y `storage.list(path:, searchOptions:)` en `Api.photoUrl`.
7. `ChatRoomScreen` (community/chat_room_screen.dart): `Iterable<int>.reduce(min)`, subida con `storage.uploadBinary` y `FileOptions`. 8. Patrones de Dart 3 con registros: `card_screen.dart` (`switch ((hasCard, status))`) y `modes.dart` (`final (levels, mode) = data`).
9. El CI ejecuta `flutter analyze --no-fatal-infos`: los **avisos** (warnings, p. ej. imports sin usar) sí rompen el build; los infos no.

## Cómo compilar
```
cd flutter/fwt_auth/wft
flutter create --platforms=android --project-name=wft .   # solo añade archivos que falten (gradle wrapper, etc.)
flutter pub get
flutter analyze --no-fatal-infos
flutter test
flutter build apk --release       # salida: build/app/outputs/flutter-apk/app-release.apk
```
En GitHub: Actions → "APK Frederick Android" → Run workflow. Publica un prerelease con `Frederick-Escolar.apk`.

Firma: sin secretos usa la clave de depuración (cada compilación tiene una distinta y obliga a desinstalar para actualizar). Para firma estable, crear un keystore y los secretos `FWT_KEYSTORE_BASE64`, `FWT_KEYSTORE_PASSWORD`, `FWT_KEY_ALIAS`, `FWT_KEY_PASSWORD` (ver `ANDROID.md`). **Nunca** subas el keystore ni contraseñas al repositorio ni a un chat.

## Qué usa la app del servidor (no lo cambies sin avisar)
Todo viene de la web ya existente; las funciones y políticas están en `supabase/migrations/`.
- Inicio de sesión: Edge Function `auth-login` (límite de intentos). Luego `auth.setSession(refresh_token)`.
- Acceso del usuario: RPC `get_my_access` (id, email, full_name, phone, role, must_change_password, permissions[]).
- Comunidad: RPC `school_chat_list`, `school_chat_messages_page`, `school_chat_send`, `school_chat_create`, `school_chat_join`, `school_chat_direct`, `school_chat_people`, `school_chat_remove`, `school_person_card`, `school_profiles`; bucket `school-chat` (fotos de mensajes). Consejo: `submit_council_application` y tabla `council_applications`.
- Tablas: `announcements`, `school_levels`, `subjects`, `grades` (con `subjects`, `grade_periods`), `student_details`, `technical_specialties`, `profile_customizations`, `profiles`, `enrollment_requests`, `nfc_cards`, `elections`, `election_lists`, `vote_receipts`, `school_polls` (+ `school_poll_options`).
- RPC: `get_academic_ranking`, `get_subject_ranking`, `cast_vote`, `submit_enrollment`, `profile_privacy_settings`, `ack_password_changed`, `public_registration_mode`, y para el terminal `terminal_scan`, `log_terminal_event`, `authorize_terminal_card` (solo la web), `consume_terminal_unlock`, `record_attendance_nfc`, `scan_school_poll_card`, `cast_school_poll_vote`.
- **Registro de tarjetas y activación (2 de noviembre)**: la web ya no lee NFC; todo se hace en la app y solo lo hace un administrador (permiso `cards.register`, función `can_register_cards`). Modo «Registrar tarjetas» (`RegistrationMode` en `terminal/modes.dart`): (1) *Persona nueva*: leer tarjeta + nombre + estudiante/docente + curso → Edge Function `terminal-register-card` (crea una cuenta pendiente con correo provisional y contraseña aleatoria que nadie conoce); (2) *Ya tiene cuenta*: `terminal_search_people` + `terminal_assign_card(p_card_uid,p_profile_id,p_replace)` para asignar o reemplazar una tarjeta. Cuando una persona con `profile.activation_pending = true` abre su perfil, aparece «Activar mi acceso a la web»: llama `terminal_issue_activation_code(p_card_uid)` y muestra un código de 8 caracteres válido **24 horas** y de un solo uso (se puede pedir otro mientras no haya correo vinculado; el nuevo anula el anterior). La persona lo usa en la web (`index.html` → «Primera vez: activar mi cuenta») con su correo y su contraseña: Edge Function `activate-account`. Bloquear/desbloquear una tarjeta: `set_card_active` (desde la web). La web muestra el directorio con `list_card_directory`.
- **PIN del administrador (2 de noviembre)**: al leer una tarjeta de administrador, `terminal_scan` devuelve `pin_set` y `pin_ok`. La app (`terminal/pin_gate.dart`, `askAdminPin`) pide crear el PIN de 6 dígitos (`terminal_pin_set`) o escribirlo (`terminal_pin_verify`; devuelve `ok`, `attempts_left` o `locked_until`) antes de abrir el panel, desbloquear o registrar tarjetas. Una verificación abre una sesión de administrador de 10 minutos (`terminal_admin_session_status`, `terminal_end_admin_session`); mientras dure, `pin_ok` es true y no se vuelve a pedir. «Registrar tarjetas» muestra una pantalla de espera hasta que hay sesión (`TerminalCtx.adminUnlock`). El PIN olvidado se restablece en la web (Seguridad).
- **Primera tarjeta de administrador (instalación nueva)**: sin ninguna tarjeta de administrador nadie puede abrir el panel ni registrar tarjetas. Al iniciar sesión con la cuenta administrativa, el terminal consulta `admin_card_registration_status()`; si es false muestra el aviso «Falta la tarjeta de administrador» con el botón «Registrar mi tarjeta de administrador» (`TerminalShell._registerFirstAdminCard`), que llama `register_initial_admin_card(p_card_uid)` (una sola vez, solo rol admin). Después se acerca esa tarjeta, se crea el PIN y ya se pueden registrar las demás. Hacerlo justo después de instalar el terminal, antes de dejarlo a la vista.
- Storage: bucket `profile-photos` (ruta `<id>/avatar`), `election-photos` (URLs firmadas).
- La autorización real la exigen RLS y las funciones; la app solo oculta o muestra opciones.

## Reglas de seguridad y de trabajo
- No incluyas claves de servicio, contraseñas ni credenciales. La clave `sb_publishable_…` de `core/config.dart` es pública por diseño.
- No apliques migraciones ni cambies Supabase de producción sin revisar el estado remoto. Esta tarea no lo requiere.
- Un UID NFC identifica una tarjeta pero **no** es un secreto; la validación va en servidor. No prometas un bloqueo imposible de evadir: la fijación de pantalla de Android la puede retirar el propietario.
- Cambios pequeños y completos; conserva el comportamiento existente. Explica qué cambiaste.
- No toques `flutter/legacy/`: es código anterior que no se compila (incluye `otra_implementacion_14h/`, una implementación paralela sin `main.dart` ni `pubspec`).

## Qué no está hecho todavía
Moderación de la comunidad (retirar mensajes ajenos, suspender escritura, cerrar foros), revisión de postulaciones, administración (usuarios, roles, importar notas CSV, auditoría), recuperación de contraseña dentro de la app (hoy envía el correo y se completa en la web), y la fuente Inter (Flutter no carga `.woff2`).

## Pruebas que solo puede hacer una persona con el teléfono (Realme C55)
1. Inicio de sesión, cierre de sesión y modo claro/oscuro/sistema.
2. Lectura NFC con una tarjeta real: la hoja "Acerca la tarjeta al teléfono" debe cerrarse sola al leer.
3. Pantalla principal: acercar una tarjeta de estudiante y de docente; debe abrir su perfil sin tocar nada y volver a leer al terminar. Probar también con la pantalla apagada y encendida.
4. Terminal: elegir "Terminal escolar", aceptar la fijación de pantalla, acercar una tarjeta de estudiante (perfil se queda abierto hasta cerrarlo), acercar la de un administrador (abre el panel), crear/abrir/cerrar una votación, fijarla en el terminal, reiniciar la app y comprobar que el modo sigue fijo, registrar asistencia, votar por turno y desbloquear.
5. Comunidad: crear un grupo, escribir en el foro, mandar una foto, abrir un perfil privado y uno público, enviar un mensaje privado.
6. Postulaciones: enviar una lista cuando la convocatoria esté abierta.
7. Rotación y botón Atrás (en terminal debe pedir la tarjeta del administrador).

## Qué entregar al terminar
1. Lista de errores corregidos (archivo y motivo).
2. Resultado de `flutter analyze` y `flutter test`, o la aclaración de que no pudiste ejecutarlos.
3. El APK o el enlace a la ejecución de GitHub Actions que lo genera.
4. Lo que quedó sin comprobar.

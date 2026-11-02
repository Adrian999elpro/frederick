# Instrucciones para ChatGPT: cambios en Supabase y en la web (Frederick)

Lee primero `CONTEXTO_APK_PARA_CHATGPT.md` (la app Android y su flujo de terminal) y las migraciones en `supabase/migrations/`, sobre todo `20261018071510_council_and_custom_polls.sql` y `20261018072034_terminal_card_access.sql`.

**Nada de esto es obligatorio para que la app funcione.** Con los permisos que ya existen, la app nueva funciona tal cual. Estos cambios la hacen más robusta y dejan un registro de lo que hace el terminal. Haz los cambios en este orden y no mezcles más cosas de las que se piden.

Reglas generales (iguales a las migraciones existentes):
- Una migración nueva por bloque, con nombre `2026110112xxxx_descripcion.sql` (posterior a `20261018073455`).
- Funciones `security definer`, `set search_path=''`, nombres de tablas con el prefijo `public.`.
- `revoke all ... from public, anon;` y `grant execute ... to authenticated;` en cada función nueva.
- Tablas nuevas con RLS activado y `revoke all ... from anon, authenticated`; el acceso solo por funciones.
- No cambies ni borres las funciones existentes `authorize_terminal_card`, `terminal_student_profile`, `consume_terminal_unlock` salvo donde se indica. La web (`web/js/terminal.js`) las usa.
- No apliques nada a producción sin pasar antes las pruebas del final (estilo `tests/polls-terminal.integration.sql`).

---

## 0. Comprobaciones previas (no cambian código)

1. La cuenta que se usará en el teléfono debe tener rol `admin`, `rector` o `encargado_consejo`. Esos roles ya tienen `terminal.operate`, `terminal.unlock`, `council.open`, `polls.manage`, `polls.operate`, `council.review` y `nfc.attendance`. Confírmalo con una consulta a `role_permissions` y dime el resultado.
2. Solo los roles de administración deben tener `terminal.unlock`, porque **la tarjeta de cualquier rol con ese permiso abre el panel del terminal**. Comprueba que ningún rol de docente o estudiante lo tenga. Si lo tiene alguno, avísame antes de quitarlo.
3. Las tarjetas de los administradores deben estar vinculadas y activas desde «Tarjetas NFC» en la web.

---

## 1. Función `terminal_scan` (recomendado, prioridad alta)

**Para qué.** Hoy la app, por cada tarjeta, llama primero a `authorize_terminal_card` y, si falla, llama a `terminal_student_profile`. Son dos viajes y la app tiene que adivinar «no es administrador» a partir de un error, lo que confunde una tarjeta de estudiante con una sesión caducada. `terminal_scan` hace las dos cosas y responde qué tipo de tarjeta es.

**Contrato.**

```sql
public.terminal_scan(p_card_uid text) returns jsonb
```

- Si `auth.uid()` es nulo o no tiene `terminal.operate`: `raise exception 'forbidden' using errcode='42501'`.
- Normaliza el UID igual que las otras funciones: `upper(regexp_replace(c.card_uid,'[^0-9A-Fa-f]','','g'))=upper(regexp_replace(p_card_uid,'[: -]','','g'))`.
- Busca la tarjeta activa de un perfil con `status='active'`. Si no hay: `raise exception 'invalid_card'`.
- **Si el rol del dueño de la tarjeta tiene `terminal.unlock`** (misma comprobación que `authorize_terminal_card`):
  - Inserta un ticket en `terminal_unlock_tickets` guardando quién es el dueño de la tarjeta (ver la columna nueva abajo).
  - Devuelve `{"kind":"admin","ticket":"<uuid>","name":"<full_name>"}`.
  - No devuelve datos personales ni notas.
- **En cualquier otro caso:** hace exactamente lo que hace hoy `terminal_student_profile` (guarda el acceso a la foto en `terminal_profile_access` por 2 minutos y arma el mismo JSON de perfil) y devuelve `{"kind":"person","profile":{...mismo json...}}`.
- Evita copiar y pegar: extrae el armado del perfil a una función interna y úsala en las dos funciones.

**Columna nueva** en `terminal_unlock_tickets`:

```sql
alter table public.terminal_unlock_tickets add column card_profile_id uuid references public.profiles(id);
```

`authorize_terminal_card` también debe rellenarla (cambio mínimo con `create or replace`, sin alterar lo demás).

**Después de aplicarla**, avísame y yo cambio la app para que use una sola llamada (`terminal_scan`) en vez de dos. No toques los archivos de Flutter.

---

## 2. Registro de actividad del terminal (recomendado, prioridad media)

**Para qué.** Que quede escrito quién abrió el panel, qué cambió y cuándo se desbloqueó el teléfono.

**Tabla.**

```sql
create table public.terminal_events(
  id bigint generated always as identity primary key,
  operator_id uuid not null references public.profiles(id),  -- cuenta con sesión en el teléfono
  actor_id uuid references public.profiles(id),              -- dueño de la tarjeta de administrador
  event text not null check (event in ('admin_card','mode_changed','poll_pinned','poll_created','poll_status','applications_toggled','unlock')),
  detail jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index terminal_events_created_idx on public.terminal_events(created_at desc);
```

RLS activado y sin permisos directos.

**Funciones.**

1. `log_terminal_event(p_ticket uuid, p_event text, p_detail jsonb default '{}')` devuelve `void`.
   - Exige `terminal.operate`.
   - El ticket debe ser de `auth.uid()` y haber sido emitido hace menos de 15 minutos (`expires_at > now() - interval '15 minutes'`). No exige que esté sin usar, porque el desbloqueo lo consume.
   - Guarda `actor_id = ticket.card_profile_id`. Limita `p_detail` a 2 000 caracteres.
2. `terminal_scan` registra solo el evento `admin_card` (nunca las lecturas de estudiantes: no se guarda qué estudiante vio su perfil).
3. Reemplaza `consume_terminal_unlock` (con `create or replace`) para que, cuando el ticket se consuma bien, inserte un evento `unlock`. Debe seguir devolviendo `boolean` igual que ahora.
4. `list_terminal_events(p_limit int default 100)` devuelve las últimas filas, con el nombre del operador y del actor. Exige `has_permission('users.manage')`. Máximo 500.

La app llamará a `log_terminal_event` al cambiar de modo, fijar una votación, crear una votación, abrir o cerrar una votación y abrir o cerrar postulaciones. Eso lo conecto yo en la app; tú solo entrega las funciones.

---

## 3. Vista en la web para el registro (prioridad media, depende del punto 2)

En la web, junto a las vistas de administración (mira `web/js/views/` y cómo `app.js` registra rutas y menú):

- Nueva vista «Actividad del terminal» visible solo con `users.manage`.
- Tabla con fecha, cuenta del teléfono, administrador que usó su tarjeta, evento y detalle, usando `list_terminal_events`.
- Sigue el estilo de las vistas existentes (por ejemplo `polls.js`): `sb.rpc(...)`, `esc()` para todo texto, `showError`, `$`, `fmtDate`. Sin librerías nuevas.
- Actualiza la versión de caché (`?v=...`) igual que hacen los demás archivos cuando los cambias.
- No cambies `web/js/terminal.js` ni sus modos.

---

## 4. Opcional: ajustes del terminal guardados en el servidor (solo si quieres)

La app ya guarda el modo y la votación fijados en el propio teléfono, y se borran al cerrar sesión. Esto bastaría para un solo teléfono. Solo haz este punto si quieres que **sobrevivan a reinstalar la app o a un teléfono nuevo con la misma cuenta**.

- Tabla `terminal_settings(operator_id uuid primary key references profiles(id), mode text not null default 'profile' check (mode in ('profile','announcements','attendance','polls','card-registration')), poll_id uuid references school_polls(id) on delete set null, updated_by uuid references profiles(id), updated_at timestamptz not null default now())`.
- `get_terminal_settings()` devuelve la fila de `auth.uid()` o los valores por defecto. Exige `terminal.operate`.
- `set_terminal_settings(p_ticket uuid, p_mode text, p_poll_id uuid default null)`. Exige `terminal.operate` y un ticket de `auth.uid()` emitido por `terminal_scan` o `authorize_terminal_card` hace menos de 10 minutos. Sin ticket válido, error `card_required`. Registra el evento correspondiente si existe el punto 2.
- Ojo con el límite actual: los tickets duran 60 segundos y se gastan al desbloquear; este punto exige aceptar la ventana de 10 minutos solo para este uso. No toques la duración de los tickets de desbloqueo.

---

## Lo que NO debes hacer

- No muevas las acciones de votaciones (`create_school_poll`, `change_school_poll_status`, `set_council_applications_open`) detrás de la tarjeta. Funcionan con la sesión administrativa del teléfono y está decidido así.
- No guardes qué estudiante vio su perfil ni sus notas en ningún registro.
- No devuelvas fotos ni notas desde `terminal_scan` cuando la tarjeta sea de administrador.
- No cambies la política de `profile_photo_visible` ni el límite de 2 minutos del acceso a fotos.

---

## Pruebas que debes entregar (archivo `tests/terminal-scan.integration.sql`, mismo estilo que `tests/polls-terminal.integration.sql`)

1. Un usuario sin `terminal.operate` recibe `forbidden` en `terminal_scan`.
2. Una tarjeta de administrador devuelve `kind='admin'` con un ticket, y **sin** claves `profile` ni `grades`.
3. Una tarjeta de estudiante devuelve `kind='person'` con `profile.id`, `profile.grades` y deja una fila en `terminal_profile_access` con `expires_at` unos 2 minutos adelante. No se crea ningún ticket.
4. Una tarjeta inexistente o inactiva devuelve `invalid_card`.
5. El ticket de `terminal_scan` funciona con `consume_terminal_unlock` una vez, y la segunda vez devuelve `false`.
6. `consume_terminal_unlock` deja exactamente un evento `unlock` con el `actor_id` correcto.
7. `log_terminal_event` rechaza un ticket de otro operador y un ticket de más de 15 minutos.
8. `list_terminal_events` falla sin `users.manage` y devuelve filas con ese permiso.
9. Ninguna fila de `terminal_events` contiene UIDs de tarjeta ni notas.

Al terminar entrégame: los archivos de migración, el archivo de pruebas, el resultado de las pruebas y la lista exacta de funciones nuevas con sus firmas, para que adapte la app.

# Publicar todo sin ChatGPT (gratis, paso a paso, Windows)

Orden obligatorio: **1 Supabase → 2 GitHub → 3 APK**. Si algo falla, detente y copia el mensaje de error tal cual para pedir ayuda.

## 0. Antes de empezar
- Descomprime el ZIP `frederick-completo-2026-11-02.zip` en una carpeta (por ejemplo `C:\frederick`). Dentro verás la carpeta `proj`.
- Tienes un solo Supabase con datos reales (Frederickconsejo) y el plan gratuito no tiene copias de seguridad. Por eso hacemos un chequeo antes de tocar nada.

## 1. Supabase (panel web, sin instalar nada)
**1.1 Ver qué migraciones ya están aplicadas.** Supabase → *SQL Editor* → *New query* → pega esto y pulsa *Run*:

```sql
select version, name from supabase_migrations.schema_migrations order by version;
```
Si da error de que la tabla no existe, escríbelo tal cual. Si funciona, **pásame la lista** (o una captura). Con ella te digo cuáles faltan antes de aplicar nada.

**1.1b Verificación previa (solo lectura, no cambia nada).** Abre `supabase\preflight_produccion.sql`, copia todo, pégalo en una consulta nueva y pulsa *Run*. Devuelve filas `descripcion | ok`.
- Las filas que empiezan con **"NO existe…"** deben salir `true` (significa que las migraciones nuevas aún no se aplicaron).
- Todas las demás también deben salir `true`.
- Si alguna sale `false`, **no apliques nada** y pásame el resultado.

**1.2 Aplicar las migraciones pendientes, una por una y en este orden.** Abre cada archivo con el Bloc de notas (están en `proj\supabase\migrations\`), copia todo su contenido, pégalo en una consulta nueva del *SQL Editor* y pulsa *Run*. Debe decir *Success*. Si una da error, **no sigas** y pásame el mensaje.
1. `20261101121500_terminal_scan.sql`
2. `20261101121600_terminal_activity.sql`
3. `20261102000100_card_registration_and_activation.sql`
4. `20261102000200_terminal_admin_pin.sql`

Salta las que ya salieron en la lista del paso 1.1. Cada archivo se aplica entero o no se aplica nada.

**1.3 Funciones del servidor.** Necesitas Node.js (gratis, https://nodejs.org, versión LTS). Abre *PowerShell* y ejecuta, uno por uno:

```powershell
cd C:\frederick\proj
npx supabase login
npx supabase link --project-ref kskzurpimoggbzuvwzts
npx supabase functions deploy terminal-register-card --use-api
npx supabase functions deploy activate-account --no-verify-jwt --use-api
npx supabase functions deploy admin-users --use-api
npx supabase functions deploy auth-login --no-verify-jwt --use-api
```
(`login` abre el navegador para que autorices; `link` puede pedir la contraseña de la base de datos: es la que pusiste al crear el proyecto.) Comprueba en *Edge Functions* del panel que aparecen las dos nuevas.

## 2. GitHub (publica la web y dispara el APK)
Elige una forma:

**A) GitHub Desktop (la más cómoda):** instala GitHub Desktop (gratis) y clona tu repositorio `Adrian999elpro/frederick`. Copia el contenido de `proj\` encima de la carpeta clonada, aceptando reemplazar. **Borra estos 6 archivos** de la carpeta clonada: `web\js\terminal.js`, `web\js\nfc-reader.js`, `web\js\views\attendance.js`, `web\js\views\card-registration.js`, `web\js\views\kiosk-profile.js`, `web\js\views\my-card.js`. En GitHub Desktop escribe un resumen («Registro de tarjetas, PIN y activación de cuentas») → *Commit to main* → *Push origin*.

**B) Desde la página de GitHub:** en el repositorio, *Add file → Upload files* y arrastra las carpetas `web`, `supabase`, `tests`, `flutter` y los `.md`. Luego abre cada uno de los 6 archivos de arriba y pulsa el icono de la papelera → *Commit changes*.

Al subir, **dos flujos se activan solos** (pestaña *Actions* del repositorio):
- «Publicar web FWT»: publica la página. Tarda 1–2 minutos. Después pulsa Ctrl+F5 en la web.
- «APK Frederick Android»: compila la app (10–20 minutos).

## 3. El APK
- En *Actions → APK Frederick Android*, cuando salga la palomita verde, ve a *Releases* (columna derecha del repositorio): ahí está `Frederick-Escolar.apk`. Descárgalo en el teléfono e instálalo (permite instalar de orígenes desconocidos).
- Si el flujo sale en **rojo**: abre la ejecución, pulsa el paso que falló (marcado con ❌) y copia las **últimas 40 líneas** del registro. Pégamelas y lo corrijo; es normal que la primera compilación falle por algún detalle, porque el código de la app nunca se compiló.
- Mientras no crees un keystore (ver `ANDROID.md`), cada versión se firma con una clave de prueba distinta: Android te pedirá desinstalar la anterior antes de instalar la nueva. No pasa nada con tus datos, que están en Supabase.

## 4. Después, en el teléfono
1. Inicia sesión con tu cuenta administrativa.
2. Pulsa «Registrar mi tarjeta de administrador» cuando tengas la tarjeta NFC.
3. Vuelve a acercarla para crear tu PIN y sigue con el modo «Registrar tarjetas».

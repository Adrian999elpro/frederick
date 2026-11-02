# Frederick Escolar (app Android)

App Flutter nativa del colegio. Usa Supabase (mismas tablas, permisos y funciones que la web).

- `lib/core/`: configuración, tema (claro/oscuro/sistema), acceso a Supabase, puente NFC.
- `lib/screens/`: inicio de sesión, inicio, carnet, ranking, votar, notas y perfil.
- `lib/community/`: foro, grupos, mensajes privados con fotos y perfiles de personas.
- `lib/terminal/`: modo terminal escolar (asistencia, votaciones por tarjeta, registro, consulta).
- `android/.../MainActivity.kt`: lector NFC y fijación de pantalla.

Compilación y pruebas: ver `.github/workflows/android.yml` y `ANDROID.md`.

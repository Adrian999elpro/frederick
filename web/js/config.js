// Configuración del frontend. Estos valores son públicos por diseño (clave anon/publishable).
// NUNCA pongas aquí la clave service_role.
export const CONFIG = {
  SUPABASE_URL: "https://kskzurpimoggbzuvwzts.supabase.co",
  SUPABASE_ANON_KEY: "sb_publishable_Ti8PUJ0hmDq67kpEvhAgxA_qgdygaUA",

  // Identidad (reutiliza el módulo en otro sistema cambiando solo estas líneas)
  APP_NAME: "Unidad Educativa Técnica Particular Frederick Winslow Taylor",
  APP_SHORT: "FWT",
  TAGLINE: "Calidad más no cantidad",
  LOGO_URL: "https://www.frederickwinslowtaylor.com/Imagenes/sello.png", // idealmente cópialo a /img y usa "img/sello.png"

  IDLE_MINUTES: 20,          // cierre de sesión por inactividad
  PERSIST_SESSION: false,    // false = la sesión muere al cerrar la pestaña (más seguro)
  ACCESS_TTL_MS: 5 * 60_000, // caché de rol/permisos en la interfaz (el servidor siempre valida)
  MIN_PASSWORD: 10,
};

/// Configuración pública de la app. La clave es la «publishable» (pública por diseño).
/// Nunca incluyas aquí la clave service_role ni contraseñas.
class AppConfig {
  static const supabaseUrl = 'https://kskzurpimoggbzuvwzts.supabase.co';
  static const anonKey = 'sb_publishable_Ti8PUJ0hmDq67kpEvhAgxA_qgdygaUA';

  static const appName = 'Frederick Escolar';
  static const schoolName = 'Unidad Educativa Técnica Particular Frederick Winslow Taylor';
  static const tagline = 'Calidad más no cantidad';
  static const logoUrl = 'https://www.frederickwinslowtaylor.com/Imagenes/sello.png';

  static const minPassword = 10;
  static const registerRedirect = 'https://adrian999elpro.github.io/frederick/index.html';
}

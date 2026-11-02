/// Configuración pública (clave anon/publishable). Nunca incluir la clave service_role.
class FwtConfig {
  const FwtConfig({
    required this.supabaseUrl,
    required this.anonKey,
    this.appName = 'Unidad Educativa Técnica Particular Frederick Winslow Taylor',
    this.tagline = 'Calidad más no cantidad',
    this.logoUrl = 'https://www.frederickwinslowtaylor.com/Imagenes/sello.png',
    this.resetRedirectUrl = '', // URL de la página web de restablecimiento: https://tu-sitio/index.html?view=reset
    this.idleMinutes = 20,
    this.minPassword = 10,
  });

  final String supabaseUrl;
  final String anonKey;
  final String appName;
  final String tagline;
  final String logoUrl;
  final String resetRedirectUrl;
  final int idleMinutes;
  final int minPassword;
}

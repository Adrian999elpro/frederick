const portalUrl = 'https://adrian999elpro.github.io/frederick/';
bool allowedPortalUrl(String value) {
  final uri = Uri.tryParse(value);
  return uri != null && uri.scheme == 'https' && uri.host == 'adrian999elpro.github.io' && (uri.port == 443) && uri.userInfo.isEmpty && uri.path.startsWith('/frederick/');
}

import 'package:flutter_test/flutter_test.dart';
import 'package:wft/portal_policy.dart';
void main() {
  test('El portal y sus pantallas están permitidos', () {
    expect(allowedPortalUrl(portalUrl), isTrue);
    expect(allowedPortalUrl('${portalUrl}app.html#my-card'), isTrue);
    expect(allowedPortalUrl('${portalUrl}index.html?view=verify'), isTrue);
  });
  test('Bloquea páginas externas, HTTP, rutas ajenas y hosts engañosos', () {
    for (final url in ['http://adrian999elpro.github.io/frederick/', 'https://evil.example/frederick/', 'https://adrian999elpro.github.io.evil.example/frederick/', 'https://adrian999elpro.github.io/otro/', 'javascript:alert(1)', 'https://user@adrian999elpro.github.io/frederick/']) {
      expect(allowedPortalUrl(url), isFalse, reason: url);
    }
  });
}

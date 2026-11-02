import 'package:shared_preferences/shared_preferences.dart';

/// Modo y votación del terminal. Se guardan para que sobrevivan a un reinicio y solo
/// cambien cuando un administrador lo autorice con su tarjeta.
class TerminalPrefs {
  static const _modeKey = 'terminal_mode';
  static const _pollKey = 'terminal_poll';

  static Future<({String mode, String? pollId})> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      return (mode: p.getString(_modeKey) ?? 'profile', pollId: p.getString(_pollKey));
    } catch (_) {
      return (mode: 'profile', pollId: null);
    }
  }

  static Future<void> save(String mode, String? pollId) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_modeKey, mode);
      if (pollId == null) {
        await p.remove(_pollKey);
      } else {
        await p.setString(_pollKey, pollId);
      }
    } catch (_) {}
  }
}

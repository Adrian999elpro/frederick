import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/api.dart';
import 'core/config.dart';
import 'core/theme.dart';
import 'core/theme_controller.dart';
import 'screens/login_screen.dart';
import 'screens/session_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
  await ThemeController.instance.load();
  await Api.init();
  runApp(const FrederickApp());
}

class FrederickApp extends StatelessWidget {
  const FrederickApp({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: ThemeController.instance,
        builder: (context, _) => MaterialApp(
          title: appName,
          debugShowCheckedModeBanner: false,
          theme: fwtTheme(Brightness.light),
          darkTheme: fwtTheme(Brightness.dark),
          themeMode: ThemeController.instance.mode,
          home: const _AuthSwitch(),
        ),
      );
}

/// Muestra el inicio de sesión o la app según haya sesión.
class _AuthSwitch extends StatelessWidget {
  const _AuthSwitch();

  @override
  Widget build(BuildContext context) => StreamBuilder<AuthState>(
        stream: Api.instance.client.auth.onAuthStateChange,
        builder: (context, _) => Api.instance.hasSession ? const SessionGate() : const LoginScreen(),
      );
}

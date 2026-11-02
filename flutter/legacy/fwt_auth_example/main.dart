import 'package:flutter/material.dart';
import 'package:fwt_auth/fwt_auth.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FwtAuth.init(const FwtConfig(
    supabaseUrl: 'https://TU-PROYECTO.supabase.co',
    anonKey: 'TU_CLAVE_ANON_O_PUBLISHABLE',
    appName: 'Unidad Educativa Técnica Particular Frederick Winslow Taylor',
    tagline: '#Calidad Más No Cantidad',
    logoUrl: 'https://www.frederickwinslowtaylor.com/Imagenes/sello.png',
  ));
  runApp(const FwtApp());
}

class FwtApp extends StatelessWidget {
  const FwtApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'FWT Escolar',
        debugShowCheckedModeBanner: false,
        theme: fwtTheme(Brightness.light),
        darkTheme: fwtTheme(Brightness.dark),
        home: AuthGate(signedIn: (context, access) => MainKioskShell(access: access)),
      );
}

class MainKioskShell extends StatefulWidget {
  const MainKioskShell({super.key, required this.access});
  final Access access;

  @override
  State<MainKioskShell> createState() => _MainKioskShellState();
}

class _MainKioskShellState extends State<MainKioskShell> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final a = widget.access;

    // Menús según permisos institucionales y roles
    final tabs = <({String label, IconData icon, Widget page})>[
      // 1. Asistencia por Sensor NFC (Diaria única)
      if (a.can('nfc.attendance') || a.role == 'admin')
        (
          label: 'Asistencia',
          icon: Icons.contactless_outlined,
          page: const NfcAttendanceScreen(),
        ),

      // 2. Votaciones con Sensor NFC
      if (a.can('nfc.attendance') || a.role == 'admin')
        (
          label: 'Votación NFC',
          icon: Icons.how_to_vote_outlined,
          page: const NfcVoteScreen(),
        ),

      // 3. Registro y Asignación de Tarjetas NFC
      if (a.can('nfc.manage') || a.role == 'admin')
        (
          label: 'Registrar Tarjeta',
          icon: Icons.credit_card_outlined,
          page: const NfcCardRegisterScreen(),
        ),

      // 4. Rankings y Cuadro de Honor (Por Especialidad y Materias)
      (
        label: 'Rankings',
        icon: Icons.emoji_events_outlined,
        page: const RankingScreen(),
      ),

      // 5. Cartelera de Novedades y Anuncios
      (
        label: 'Novedades',
        icon: Icons.campaign_outlined,
        page: const AnnouncementsScreen(),
      ),

      // 6. Estadísticas Electorales
      if (a.can('elections.stats') || a.role == 'admin')
        (
          label: 'Resultados',
          icon: Icons.bar_chart_outlined,
          page: const StatsScreen(),
        ),

      // 7. Mi Perfil (Personalización Estudiantil e Indicadores Docentes)
      (
        label: 'Mi Perfil',
        icon: Icons.person_outline,
        page: ProfileScreen(access: a),
      ),
    ];

    final activeIndex = _currentIndex.clamp(0, tabs.length - 1);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.network(
              'https://www.frederickwinslowtaylor.com/Imagenes/sello.png',
              width: 32,
              height: 32,
              errorBuilder: (_, __, ___) => const Icon(Icons.school, size: 28),
            ),
            const SizedBox(width: 8),
            const Flexible(
              child: Text(
                'FWT · Sistema Escolar',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        actions: [
          // Botón de Salir de la App: BLOQUEADO CON TARJETA DE ADMINISTRADOR
          IconButton(
            icon: const Icon(Icons.power_settings_new),
            tooltip: 'Salir de la App (Requiere Tarjeta Administrador)',
            onPressed: () => AdminKioskGuard.exitAppWithAdminCard(context),
          ),
        ],
      ),
      body: tabs[activeIndex].page,
      bottomNavigationBar: tabs.length < 2
          ? null
          : NavigationBar(
              selectedIndex: activeIndex,
              onDestinationSelected: (v) async {
                // Si está en pantalla de asistencia o votación y quiere cambiar, solicitar tarjeta admin
                if ((tabs[activeIndex].label == 'Asistencia' || tabs[activeIndex].label == 'Votación NFC') &&
                    v != activeIndex) {
                  final ok = await AdminKioskGuard.requestAdminAuth(
                    context,
                    reason: 'cambiar el modo del terminal',
                  );
                  if (!ok) return;
                }
                setState(() => _currentIndex = v);
              },
              destinations: [
                for (final t in tabs)
                  NavigationDestination(
                    icon: Icon(t.icon),
                    selectedIcon: Icon(t.icon, color: FwtColors.brand),
                    label: t.label,
                  ),
              ],
            ),
    );
  }
}

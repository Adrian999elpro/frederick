import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/config.dart';
import '../core/errors.dart';
import '../core/nfc.dart';
import '../core/theme.dart';

void snack(BuildContext context, String message, {bool error = false}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(
    content: Text(message),
    backgroundColor: error ? Fwt.brandDeep : null,
  ));
}

/// Sello del colegio; si no se puede cargar muestra un ícono.
class SchoolLogo extends StatelessWidget {
  const SchoolLogo({super.key, this.size = 56});
  final double size;

  /// El sello del colegio ya es circular y viene dentro de la app (no depende de internet).
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.28), blurRadius: size * 0.18, offset: Offset(0, size * 0.05))],
        ),
        child: Image.asset(
          'assets/logo.png',
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          semanticLabel: 'Sello de la Unidad Educativa Frederick Winslow Taylor',
          errorBuilder: (_, __, ___) => DecoratedBox(
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            child: Icon(Icons.school_rounded, size: size * 0.6, color: Fwt.brand),
          ),
        ),
      );
}

/// Foto de perfil o, si no hay, la inicial del nombre.
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.name, this.url, this.size = 48});
  final String name;
  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    final fallback = Center(
      child: Text(initial, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: size * 0.42)),
    );
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(shape: BoxShape.circle, gradient: Fwt.heroGradient),
      clipBehavior: Clip.antiAlias,
      child: url == null
          ? fallback
          : Image.network(url!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback),
    );
  }
}

/// Cabecera con degradado rojo, usada en la parte superior de las pantallas principales.
class HeroHeader extends StatelessWidget {
  const HeroHeader({super.key, required this.child, this.padding});
  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: padding ?? EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 16, 20, 24),
        decoration: const BoxDecoration(
          gradient: Fwt.heroGradient,
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
        ),
        child: child,
      );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.action});
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
        child: Row(children: [
          Expanded(child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
          if (action != null) action!,
        ]),
      );
}

/// Mensaje vacío o de error con ícono y acción opcional.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.text, this.actionLabel, this.onAction});
  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 52, color: context.muted),
            const SizedBox(height: 14),
            Text(text, textAlign: TextAlign.center, style: TextStyle(color: context.muted, fontSize: 15, height: 1.4)),
            if (actionLabel != null) ...[
              const SizedBox(height: 18),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ]),
        ),
      );
}

/// Carga datos, muestra progreso o error con "Reintentar" y permite recargar deslizando.
class AsyncView<T> extends StatefulWidget {
  const AsyncView({super.key, required this.load, required this.builder, this.refreshKey});
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, Future<void> Function() reload) builder;
  final Object? refreshKey;

  @override
  State<AsyncView<T>> createState() => _AsyncViewState<T>();
}

class _AsyncViewState<T> extends State<AsyncView<T>> {
  late Future<T> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.load();
  }

  @override
  void didUpdateWidget(covariant AsyncView<T> old) {
    super.didUpdateWidget(old);
    if (old.refreshKey != widget.refreshKey) _reloadNow();
  }

  void _reloadNow() => setState(() => _future = widget.load());

  Future<void> _reload() async {
    final next = widget.load();
    setState(() => _future = next);
    try {
      await next;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return EmptyState(
              icon: Icons.cloud_off_rounded,
              text: friendlyError(snapshot.error!),
              actionLabel: 'Reintentar',
              onAction: _reloadNow,
            );
          }
          return widget.builder(context, snapshot.data as T, _reload);
        },
      );
}

/// Hoja inferior que espera una tarjeta NFC. Devuelve el UID o null si se cancela.
Future<String?> scanCard(BuildContext context, {String title = 'Acerca la tarjeta al teléfono'}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (_) => _ScanSheet(title: title),
  );
}

class _ScanSheet extends StatefulWidget {
  const _ScanSheet({required this.title});
  final String title;

  @override
  State<_ScanSheet> createState() => _ScanSheetState();
}

class _ScanSheetState extends State<_ScanSheet> {
  String? _error;
  bool _scanning = true;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() {
      _error = null;
      _scanning = true;
    });
    try {
      // Libera cualquier lectura que otra pantalla (p. ej. la lectura continua) tenga en curso.
      await Nfc.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      if (!mounted) return;
      final uid = await Nfc.scan();
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.of(context).pop(uid);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = friendlyError(e, 'No se pudo leer la tarjeta.');
          _scanning = false;
        });
      }
    }
  }

  @override
  void dispose() {
    Nfc.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ScanRipple(active: _scanning, error: _error != null),
          const SizedBox(height: 18),
          Semantics(
            liveRegion: true,
            child: Text(_error ?? widget.title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 6),
          Text(_error == null ? 'Buscando la tarjeta NFC…' : 'Puedes intentarlo de nuevo.',
              style: TextStyle(color: context.muted)),
          const SizedBox(height: 22),
          if (_error != null) ...[
            FilledButton(onPressed: _start, child: const Text('Intentar de nuevo')),
            const SizedBox(height: 10),
          ],
          OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        ]),
      );
}

/// Ondas animadas de "acerca la tarjeta".
class ScanRipple extends StatefulWidget {
  const ScanRipple({super.key, this.size = 190, this.active = true, this.error = false});
  final double size;
  final bool active;
  final bool error;

  @override
  State<ScanRipple> createState() => _ScanRippleState();
}

class _ScanRippleState extends State<ScanRipple> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, _) => CustomPaint(
            painter: _RipplePainter(widget.active ? _pulse.value : 0, !widget.error),
            child: Center(
              child: Icon(widget.error ? Icons.error_outline_rounded : Icons.contactless_rounded,
                  size: widget.size * 0.34, color: Colors.white),
            ),
          ),
        ),
      );
}

class _RipplePainter extends CustomPainter {
  _RipplePainter(this.t, this.active);
  final double t;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final base = size.width * 0.27;
    for (var i = 0; i < 3; i++) {
      final p = (t + i / 3) % 1;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Fwt.brand.withValues(alpha: (1 - p) * 0.5);
      if (t > 0) canvas.drawCircle(center, base + p * (size.width / 2 - base), paint);
    }
    canvas.drawCircle(center, base, Paint()..color = active ? Fwt.brand : Fwt.brandDeep);
    canvas.drawCircle(
      center,
      base + math.sin(t * math.pi * 2) * 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Fwt.gold.withValues(alpha: 0.7),
    );
  }

  @override
  bool shouldRepaint(covariant _RipplePainter old) => old.t != t || old.active != active;
}

/// Diálogo de confirmación simple.
Future<bool> confirm(BuildContext context, String message, {String okLabel = 'Confirmar'}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(100, 44)),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(okLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

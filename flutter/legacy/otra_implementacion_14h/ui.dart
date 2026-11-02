import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'api.dart';
import 'app_state.dart';
import 'config.dart';
import 'nfc.dart';
import 'theme.dart';

// ---------------------------------------------------------------- utilidades

String fmtDate(Object? iso, {bool time = true}) {
  final d = DateTime.tryParse('$iso')?.toLocal();
  if (d == null) return '';
  const months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
  final base = '${d.day} ${months[d.month - 1]} ${d.year}';
  if (!time) return base;
  final h = d.hour.toString().padLeft(2, '0');
  final m = d.minute.toString().padLeft(2, '0');
  return '$base, $h:$m';
}

String fmtScore(Object? v) {
  final n = v is num ? v.toDouble() : double.tryParse('$v');
  return n == null ? '—' : n.toStringAsFixed(2);
}

void showMsg(BuildContext context, String text, {bool error = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(
    content: Text(text),
    backgroundColor: error ? FwtColors.danger : null,
  ));
}

Future<bool> confirmDialog(BuildContext context, String message,
    {String okLabel = 'Confirmar', String title = '¿Seguro?'}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(110, 44)),
          onPressed: () => Navigator.pop(c, true),
          child: Text(okLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

Color scoreColor(BuildContext context, double? score) {
  if (score == null) return Theme.of(context).colorScheme.onSurfaceVariant;
  final dark = Theme.of(context).brightness == Brightness.dark;
  if (score >= 9) return FwtColors.gold;
  if (score >= 7) return dark ? FwtColors.okOnDark : FwtColors.ok;
  return dark ? FwtColors.brandOnDark : FwtColors.danger;
}

// ---------------------------------------------------------------- logo y avatar

class FwtLogo extends StatelessWidget {
  const FwtLogo({super.key, this.size = 40});
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.24),
      child: Container(
        width: size,
        height: size,
        color: Colors.white,
        padding: EdgeInsets.all(size * 0.08),
        child: Image.network(
          AppConfig.logoUrl,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stack) => Center(
            child: Text(
              'FWT',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: size * 0.3, color: FwtColors.brand),
            ),
          ),
        ),
      ),
    );
  }
}

class _PhotoEntry {
  _PhotoEntry(this.url, this.expires);
  final String? url;
  final DateTime expires;
}

class PhotoCache {
  static final Map<String, _PhotoEntry> _cache = {};

  static Future<String?> get(String userId) async {
    final hit = _cache[userId];
    if (hit != null && DateTime.now().isBefore(hit.expires)) return hit.url;
    final url = await Api.profilePhotoUrl(userId);
    _cache[userId] = _PhotoEntry(url, DateTime.now().add(const Duration(minutes: 50)));
    return url;
  }

  static void invalidate(String userId) => _cache.remove(userId);
}

class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.name, this.userId, this.size = 48, this.ring = false});
  final String name;
  final String? userId;
  final double size;
  final bool ring;

  @override
  Widget build(BuildContext context) {
    final rev = AppScope.of(context).photoRev;
    final trimmed = name.trim();
    final initial = trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      color: FwtColors.brandDeep,
      child: Text(
        initial,
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: size * 0.42),
      ),
    );
    final id = userId;
    Widget inner = fallback;
    if (id != null) {
      inner = FutureBuilder<String?>(
        key: ValueKey('$id-$rev'),
        future: PhotoCache.get(id),
        builder: (context, snap) {
          final url = snap.data;
          if (url == null) return fallback;
          return Image.network(
            url,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stack) => fallback,
          );
        },
      );
    }
    final avatar = ClipOval(child: SizedBox(width: size, height: size, child: inner));
    if (!ring) return avatar;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: [FwtColors.gold, FwtColors.accent]),
      ),
      child: avatar,
    );
  }
}

// ---------------------------------------------------------------- contenedores

class GradientHero extends StatelessWidget {
  const GradientHero({super.key, required this.child, this.bottomRadius = 32});
  final Widget child;
  final double bottomRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: FwtColors.heroGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(bottomRadius)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 24), child: child),
      ),
    );
  }
}

class FwtCard extends StatelessWidget {
  const FwtCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap, this.color});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: color ?? cs.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.action, this.onAction});
  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
      child: Row(
        children: [
          Expanded(child: Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
          if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
        ],
      ),
    );
  }
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(99)),
      child: Text(text, style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w800)),
    );
  }
}

// ---------------------------------------------------------------- estados

class LoadingBox extends StatelessWidget {
  const LoadingBox({super.key});
  @override
  Widget build(BuildContext context) =>
      const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()));
}

class EmptyBox extends StatelessWidget {
  const EmptyBox({super.key, required this.icon, required this.title, this.message});
  final IconData icon;
  final String title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 52, color: muted),
          const SizedBox(height: 12),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(message!, textAlign: TextAlign.center, style: TextStyle(color: muted)),
          ],
        ],
      ),
    );
  }
}

class ErrorBox extends StatelessWidget {
  const ErrorBox({super.key, required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 48),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(160, 48)),
              onPressed: onRetry,
              child: const Text('Reintentar'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Muestra carga, error o contenido según el estado de un Future.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({super.key, required this.future, required this.builder, this.onRetry});
  final Future<T> future;
  final Widget Function(BuildContext context, T data) builder;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const LoadingBox();
        if (snap.hasError) {
          return ErrorBox(
            message: friendlyError(snap.error!, 'No se pudo cargar. Revisa tu conexión a internet.'),
            onRetry: onRetry,
          );
        }
        return builder(context, snap.data as T);
      },
    );
  }
}

// ---------------------------------------------------------------- lectura de tarjeta NFC

/// Abre una hoja con animación de ondas, espera la tarjeta y devuelve su UID (o null si se cancela).
Future<String?> askCard(BuildContext context, {String title = 'Acerca la tarjeta al teléfono'}) {
  return showModalBottomSheet<String>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    builder: (_) => _NfcSheet(title: title),
  );
}

class _NfcSheet extends StatefulWidget {
  const _NfcSheet({required this.title});
  final String title;

  @override
  State<_NfcSheet> createState() => _NfcSheetState();
}

class _NfcSheetState extends State<_NfcSheet> with SingleTickerProviderStateMixin {
  late final AnimationController _anim =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat();
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    if (mounted) setState(() => _error = null);
    try {
      final uid = await NfcBridge.scan();
      if (mounted) Navigator.pop(context, uid);
    } on NfcException catch (e) {
      if (!mounted) return;
      if (e.cancelled) return;
      setState(() => _error = e.message);
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 200,
              height: 200,
              child: AnimatedBuilder(
                animation: _anim,
                builder: (context, child) => CustomPaint(
                  painter: _WavesPainter(_anim.value, _error == null ? cs.primary : cs.error),
                  child: Center(
                    child: Icon(
                      _error == null ? Icons.contactless_rounded : Icons.error_outline_rounded,
                      size: 64,
                      color: _error == null ? cs.primary : cs.error,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error == null ? widget.title : 'No se pudo leer',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              _error ?? 'Apoya la tarjeta en la parte trasera del teléfono, cerca de la cámara.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            if (_error != null) ...[
              FilledButton(onPressed: _start, child: const Text('Intentar de nuevo')),
              const SizedBox(height: 8),
            ],
            OutlinedButton(
              onPressed: () {
                NfcBridge.cancel();
                Navigator.pop(context, null);
              },
              child: const Text('Cancelar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _WavesPainter extends CustomPainter {
  _WavesPainter(this.t, this.color);
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxR = math.min(size.width, size.height) / 2;
    for (var i = 0; i < 3; i++) {
      final p = (t + i / 3) % 1.0;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = color.withValues(alpha: (1 - p) * 0.5);
      canvas.drawCircle(center, 36 + (maxR - 36) * p, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WavesPainter old) => old.t != t || old.color != color;
}

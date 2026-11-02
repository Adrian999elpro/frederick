import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/errors.dart';
import '../core/nfc.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

/// Lectura continua de tarjetas para una pantalla: no hace falta tocar ningún botón.
/// Lee una tarjeta, espera a que [onCardRead] termine y vuelve a leer. Se pausa sola si otra
/// pantalla o ventana se abre encima, o si la app pasa a segundo plano.
mixin CardLoopMixin<T extends StatefulWidget> on State<T> {
  bool _loopAlive = false;
  bool cardBusy = false;
  String? nfcUnavailable;

  Future<void> onCardRead(String uid);

  /// Por defecto muestra el error en un aviso. Se puede sobrescribir.
  void onCardError(Object error) {
    if (mounted) snack(context, friendlyError(error, 'No se pudo completar. Vuelve a intentarlo.'), error: true);
  }

  void startCardLoop() {
    if (_loopAlive) return;
    _loopAlive = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _runLoop());
  }

  void stopCardLoop() {
    _loopAlive = false;
    Nfc.cancel();
  }

  bool get _ready =>
      mounted &&
      nfcUnavailable == null &&
      !cardBusy &&
      (ModalRoute.of(context)?.isCurrent ?? false) &&
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  Future<void> _runLoop() async {
    while (_loopAlive && mounted) {
      if (!_ready) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
        continue;
      }
      try {
        final uid = await Nfc.scan();
        if (!_loopAlive || !mounted) return;
        setState(() => cardBusy = true);
        try {
          await onCardRead(uid);
        } catch (e) {
          onCardError(e);
        } finally {
          if (mounted) setState(() => cardBusy = false);
        }
      } on PlatformException catch (e) {
        if (!mounted) return;
        if (e.code == 'unavailable') {
          setState(() => nfcUnavailable = e.message ?? 'Este teléfono no tiene NFC o está desactivado.');
        } else {
          // Tiempo agotado, lectura cancelada u ocupada: se vuelve a intentar.
          await Future<void>.delayed(const Duration(milliseconds: 600));
        }
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 600));
      }
    }
  }
}

/// Pantalla de espera con ondas NFC y un título/texto configurables.
class CardWaiting extends StatefulWidget {
  const CardWaiting({super.key, required this.onCard, required this.title, required this.hint, this.header, this.busyTitle = 'Procesando…'});

  final Future<void> Function(String uid) onCard;
  final String title;
  final String hint;
  final String busyTitle;

  /// Contenido opcional que se muestra arriba de las ondas (p. ej. la votación activa).
  final Widget? header;

  @override
  State<CardWaiting> createState() => _CardWaitingState();
}

class _CardWaitingState extends State<CardWaiting> with CardLoopMixin<CardWaiting> {
  @override
  void initState() {
    super.initState();
    startCardLoop();
  }

  @override
  void dispose() {
    stopCardLoop();
    super.dispose();
  }

  @override
  Future<void> onCardRead(String uid) => widget.onCard(uid);

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (widget.header != null) ...[widget.header!, const SizedBox(height: 18)],
            ScanRipple(size: 210, active: nfcUnavailable == null, error: nfcUnavailable != null),
            const SizedBox(height: 22),
            Semantics(
              liveRegion: true,
              child: Text(
                nfcUnavailable != null ? 'NFC no disponible' : (cardBusy ? widget.busyTitle : widget.title),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(height: 8),
            Text(nfcUnavailable ?? widget.hint, textAlign: TextAlign.center, style: TextStyle(color: context.muted, height: 1.45)),
            if (nfcUnavailable != null) ...[
              const SizedBox(height: 18),
              OutlinedButton(onPressed: () => setState(() => nfcUnavailable = null), child: const Text('Reintentar')),
            ],
          ]),
        ),
      );
}

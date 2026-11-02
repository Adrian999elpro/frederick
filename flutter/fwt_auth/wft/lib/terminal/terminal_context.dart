import 'package:flutter/material.dart';

import '../core/api.dart';

/// Resultado de leer una tarjeta con `terminal_scan`: la tarjeta es de un administrador
/// (trae un permiso de un solo uso) o de una persona (trae su perfil).
class CardScan {
  const CardScan.admin(this.ticket, this.name, {this.pinSet = false, this.pinOk = false})
      : profile = null,
        uid = null;
  const CardScan.person(this.profile, this.uid)
      : ticket = null,
        name = null,
        pinSet = false,
        pinOk = false;

  final String? ticket;
  final String? name;
  final Map<String, dynamic>? profile;

  /// UID de la tarjeta leída (solo para personas): permite pedir su código de activación.
  final String? uid;

  /// Tarjeta de administrador: ¿ya creó su PIN? ¿hay una sesión de administrador abierta
  /// (entonces no se pide el PIN otra vez)?
  final bool pinSet;
  final bool pinOk;

  bool get isAdmin => ticket != null;
}

/// Lo que el marco del terminal le da a cada modo.
class TerminalCtx {
  const TerminalCtx({
    required this.access,
    required this.mode,
    required this.pollId,
    required this.scan,
    required this.openPanel,
    required this.adminUnlock,
    required this.setMode,
  });

  final Access access;
  final String mode;

  /// Votación que el administrador dejó activa en este terminal (si hay una).
  final String? pollId;

  /// Lee la tarjeta en el servidor (`terminal_scan`) y dice si es de un administrador o de una persona.
  final Future<CardScan> Function(String uid) scan;

  /// Abre el panel del administrador (pide su PIN si hace falta).
  final Future<void> Function(CardScan scan) openPanel;

  /// Lee una tarjeta de administrador y le pide el PIN, sin abrir el panel. Devuelve true si quedó
  /// abierta la sesión de administrador (la que el servidor exige para registrar tarjetas).
  final Future<bool> Function(String uid) adminUnlock;

  final void Function(String mode, {String? pollId}) setMode;

  /// Lee la tarjeta. Si es de un administrador abre su panel y devuelve null; si es de una
  /// persona devuelve la lectura (con su perfil) para que el modo la use.
  Future<CardScan?> handleCard(String uid) async {
    final result = await scan(uid);
    if (result.isAdmin) {
      await openPanel(result);
      return null;
    }
    return result;
  }
}

class TerminalMode {
  const TerminalMode(this.id, this.label, this.icon, this.permission, this.build);
  final String id;
  final String label;
  final IconData icon;
  final String permission;
  final Widget Function(TerminalCtx ctx) build;
}

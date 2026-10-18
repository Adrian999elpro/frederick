import 'package:flutter/widgets.dart';

import '../access.dart';

/// Muestra [child] solo si el usuario tiene el permiso. Es una comodidad de interfaz:
/// la seguridad real la imponen las políticas RLS y las funciones del servidor.
class PermissionGate extends StatelessWidget {
  const PermissionGate({super.key, required this.access, required this.permission, required this.child, this.fallback});

  final Access access;
  final String permission;
  final Widget child;
  final Widget? fallback;

  @override
  Widget build(BuildContext context) => access.can(permission) ? child : (fallback ?? const SizedBox.shrink());
}

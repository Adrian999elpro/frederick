typedef Json = Map<String, dynamic>;

/// Perfil + rol + permisos tal como los devuelve el servidor (get_my_access).
/// Sirve solo para mostrar u ocultar pantallas: el servidor vuelve a exigir cada permiso.
class Access {
  const Access({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    required this.permissions,
    required this.mustChangePassword,
    this.phone,
  });

  final String id;
  final String email;
  final String fullName;
  final String? phone;
  final String role;
  final List<String> permissions;
  final bool mustChangePassword;

  bool can(String code) => permissions.contains(code);

  String get firstName {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    return parts.isEmpty || parts.first.isEmpty ? 'bienvenido' : parts.first;
  }

  factory Access.fromJson(Map<String, dynamic> j) => Access(
        id: j['id'] as String,
        email: (j['email'] ?? '') as String,
        fullName: (j['full_name'] ?? '') as String,
        phone: j['phone'] as String?,
        role: (j['role'] ?? '') as String,
        permissions: List<String>.from((j['permissions'] ?? const []) as List),
        mustChangePassword: (j['must_change_password'] ?? false) as bool,
      );
}

double? asDouble(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse('$v');
}

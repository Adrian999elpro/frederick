/// Perfil + rol + permisos del usuario, tal como los devuelve el servidor (get_my_access).
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

  /// Solo para mostrar u ocultar interfaz. El servidor vuelve a exigir cada permiso.
  bool can(String code) => permissions.contains(code);

  factory Access.fromJson(Map<String, dynamic> j) => Access(
        id: j['id'] as String,
        email: j['email'] as String,
        fullName: (j['full_name'] ?? '') as String,
        phone: j['phone'] as String?,
        role: j['role'] as String,
        permissions: List<String>.from(j['permissions'] as List),
        mustChangePassword: (j['must_change_password'] ?? false) as bool,
      );
}

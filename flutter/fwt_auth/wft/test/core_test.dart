import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wft/core/api.dart';
import 'package:wft/core/errors.dart';
import 'package:wft/community/person.dart';
import 'package:wft/core/theme.dart';

void main() {
  group('UID de tarjetas', () {
    test('normaliza separadores y minúsculas', () {
      expect(normalizeUid('04:a2:3b:5c'), '04A23B5C');
      expect(normalizeUid('04-A2 3B 5C'), '04A23B5C');
    });

    test('acepta de 4 a 10 bytes y rechaza el resto', () {
      expect(isValidUid('04:A2:3B:5C'), isTrue);
      expect(isValidUid('04:A2:3B:5C:6D:7E:8F'), isTrue);
      expect(isValidUid('04:A2'), isFalse);
      expect(isValidUid('04:A2:3B:5'), isFalse);
      expect(isValidUid('ZZ:ZZ:ZZ:ZZ'), isFalse);
      expect(isValidUid(''), isFalse);
    });
  });

  group('Mensajes de error', () {
    test('traduce códigos del servidor', () {
      expect(friendlyError(Exception('already_voted')), 'Ya registraste tu voto en esta votación.');
      expect(friendlyError(Exception('card_not_authorized')), contains('no tiene permiso'));
    });

    test('usa el mensaje de respaldo si no reconoce el error', () {
      expect(friendlyError(Exception('algo raro'), 'Respaldo'), 'Respaldo');
    });

    test('muestra el mensaje de AuthFailure tal cual', () {
      expect(friendlyError(AuthFailure('Correo o contraseña incorrectos.')), 'Correo o contraseña incorrectos.');
    });
  });

  group('Acceso', () {
    final access = Access.fromJson({
      'id': 'u1',
      'email': 'ana@colegio.ec',
      'full_name': 'Ana María Pérez',
      'role': 'estudiante',
      'must_change_password': false,
      'permissions': ['grades.read'],
    });

    test('lee permisos y rol', () {
      expect(access.isStudent, isTrue);
      expect(access.can('grades.read'), isTrue);
      expect(access.can('users.manage'), isFalse);
      expect(access.firstName, 'Ana');
    });
  });

  group('Personas de la comunidad', () {
    test('describe estudiantes, docentes y otros cargos', () {
      expect(Person(id: '1', name: 'Ana', role: 'estudiante', level: '1.º BGU').label, 'Estudiante · 1.º BGU');
      expect(Person(id: '2', name: 'Luis', role: 'docente', subjects: ['Matemática', 'Física']).label, 'Profesor/a de Matemática, Física');
      expect(Person(id: '3', name: 'Rosa', role: 'rector').label, 'Rector');
    });

    test('lee la respuesta del servidor', () {
      final p = Person.maybe({'id': 'x', 'name': 'Eva', 'role': 'docente', 'subjects': ['Arte']});
      expect(p?.name, 'Eva');
      expect(Person.maybe(null), isNull);
    });
  });

  group('Tema', () {
    test('conserva la paleta institucional', () {
      expect(Fwt.brand, const Color(0xFFA81717));
      expect(Fwt.ink, const Color(0xFF0E1117));
    });

    test('hay tema claro y oscuro', () {
      expect(fwtTheme(Brightness.light).brightness, Brightness.light);
      expect(fwtTheme(Brightness.dark).brightness, Brightness.dark);
    });
  });
}

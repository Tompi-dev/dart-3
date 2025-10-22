import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:postgres/postgres.dart';
import '../db/connection.dart';
import '../env.dart';
import '../middleware/jwt_utils.dart';

final jwtSecret = Env.get('JWT_SECRET');

class AuthRoute {
  Router get router {
    final router = Router();

    // === POST /auth/register ===
    router.post('/auth/register', (Request req) async {
      try {
        final body = await req.readAsString();
        final data = jsonDecode(body) as Map<String, dynamic>;

        final name = data['name'];
        final email = data['email'];
        final password = data['password'];
        final role = data['role'];

        if ([name, email, password, role].contains(null)) {
          return Response(
            400,
            body: jsonEncode({'error': 'Missing fields'}),
            headers: {'content-type': 'application/json'},
          );
        }

        final inserted = await connection.execute(
          Sql.named('''
            INSERT INTO users (name, email, password, role)
            VALUES (@name, @email, @password, @role)
            RETURNING id
          '''),
          parameters: {
            'name': name,
            'email': email,
            'password': password,
            'role': role,
          },
        );

        final newUserId = inserted.first[0] as int;

        if (role == 'student') {
          await connection.execute(
            Sql.named('''
              INSERT INTO students (id, is_trial)
              VALUES (@id, FALSE)
              ON CONFLICT (id) DO NOTHING
            '''),
            parameters: {'id': newUserId},
          );
        } else if (role == 'teacher') {
          await connection.execute(
            Sql.named('''
              INSERT INTO teachers (id, is_frozen)
              VALUES (@id, FALSE)
              ON CONFLICT (id) DO NOTHING
            '''),
            parameters: {'id': newUserId},
          );
        }

        print('✅ Registered new user: $email ($role)');
        return Response.ok(
          jsonEncode({'message': 'User registered successfully'}),
          headers: {'content-type': 'application/json'},
        );
      } catch (e) {
        print('❌ Error register: $e');

        final errString = e.toString();
        if (errString.contains('duplicate key value') ||
            errString.contains('23505')) {
          return Response(
            400,
            body: jsonEncode({
              'error': 'Email already exists. Please use a different one.'
            }),
            headers: {'content-type': 'application/json'},
          );
        }

        return Response.internalServerError(
          body: jsonEncode({'error': errString}),
          headers: {'content-type': 'application/json'},
        );
      }
    });

    // === POST /auth/login ===
    router.post('/auth/login', (Request req) async {
      try {
        final body = await req.readAsString();
        final data = jsonDecode(body) as Map<String, dynamic>;

        final email = data['email'];
        final password = data['password'];

        if (email == null || password == null) {
          return Response(
            400,
            body: jsonEncode({'error': 'Email and password required'}),
            headers: {'content-type': 'application/json'},
          );
        }

        final result = await connection.execute(
          Sql.named('SELECT id, role, password FROM users WHERE email = @e'),
          parameters: {'e': email},
        );

        if (result.isEmpty || result.first[2] != password) {
          return Response(
            401,
            body: jsonEncode({'error': 'Invalid credentials'}),
            headers: {'content-type': 'application/json'},
          );
        }

        final userId = result.first[0] as int;
        final role = result.first[1] as String;

        final token = generateJwt(userId, role);

        return Response.ok(
          jsonEncode({'token': token}),
          headers: {'content-type': 'application/json'},
        );
      } catch (e) {
        print('❌ Error login: $e');
        return Response.internalServerError(
          body: jsonEncode({'error': e.toString()}),
          headers: {'content-type': 'application/json'},
        );
      }
    });

    return router;
  }
}

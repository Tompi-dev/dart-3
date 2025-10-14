import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:postgres/postgres.dart'; 
import '../db/connection.dart';
import '../env.dart';

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

        await connection.execute(
          Sql.named('''
            INSERT INTO users (name, email, password, role)
            VALUES (@name, @email, @password, @role)
          '''),
          parameters: {
            'name': name,
            'email': email,
            'password': password,
            'role': role,
          },
        );

        print('✅ Registered new user: $email ($role)');
        return Response.ok(
          jsonEncode({'message': 'User registered successfully'}),
          headers: {'content-type': 'application/json'},
        );
      } catch (e) {
        print('❌ Error register: $e');
        return Response.internalServerError(
          body: jsonEncode({'error': e.toString()}),
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

        final userId = result.first[0];
        final role = result.first[1];

       
        final jwt = JWT({
          'id': userId,
          'role': role,
          'exp': DateTime.now()
              .add(const Duration(hours: 2))
              .millisecondsSinceEpoch ~/ 1000,
        });

        final token = jwt.sign(SecretKey(jwtSecret!));

        return Response.ok(
          jsonEncode({'token': token}),
          headers: {'content-type': 'application/json'},
        );
      } catch (e) {
        print('❌ Error login: $e');
        return Response.internalServerError(
          body: jsonEncode({'error': e.toString()}),
        );
      }
    });

    return router;
  }
}

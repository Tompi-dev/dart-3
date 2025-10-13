import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../db/connection.dart';
import 'package:postgres/postgres.dart' show Sql;
import '../middleware/role_guard.dart'; 

class GroupsRoute {
  Router get router {
    final router = Router();

    // ===== GET /groups =====
    router.get('/groups', (Request req) async {
      final authHeader = req.headers['Authorization'];
      if (authHeader == null || !authHeader.startsWith('Bearer ')) {
        return Response.forbidden(
          jsonEncode({'error': 'Missing or invalid Authorization header'}),
          headers: {'content-type': 'application/json'},
        );
      }

      final token = authHeader.substring(7).trim();
      final authData = verifyJwt(token);
      if (authData == null) {
        return Response.forbidden(
          jsonEncode({'error': 'Invalid or expired token'}),
          headers: {'content-type': 'application/json'},
        );
      }

      try {
        final result = await connection.execute('''
          SELECT g.id, g.name, t.id AS teacher_id, h.name AS hall_name
          FROM groups g
          LEFT JOIN teachers t ON g.teacher_id = t.id
          LEFT JOIN halls h ON g.hall_id = h.id;
        ''');

        final groups = result
            .map((row) => {
                  'id': row[0],
                  'name': row[1],
                  'teacher_id': row[2],
                  'hall_name': row[3],
                })
            .toList();

        return Response.ok(
          jsonEncode(groups),
          headers: {'content-type': 'application/json'},
        );
      } catch (e) {
        print('❌ Error fetching groups: $e');
        return Response.internalServerError(body: 'Database error');
      }
    });

    // ===== POST /groups =====
    router.post('/groups', (Request req) async {
      final authHeader = req.headers['Authorization'];
      if (authHeader == null || !authHeader.startsWith('Bearer ')) {
        return Response.forbidden(
          jsonEncode({'error': 'Missing or invalid Authorization header'}),
          headers: {'content-type': 'application/json'},
        );
      }

      final token = authHeader.substring(7).trim();
      final authData = verifyJwt(token);
      if (authData == null) {
        return Response.forbidden(
          jsonEncode({'error': 'Invalid or expired token'}),
          headers: {'content-type': 'application/json'},
        );
      }

      // 🔒 Проверка роли
      final role = authData['role'];
      if (role != 'teacher' && role != 'admin') {
        return Response.forbidden(
          jsonEncode({'error': 'Access denied. Teachers or Admins only.'}),
          headers: {'content-type': 'application/json'},
        );
      }

      try {
        final body = await req.readAsString();
        final data = jsonDecode(body) as Map<String, dynamic>;

        final name = data['name'] as String?;
        final teacherId = data['teacher_id'] as int?;
        final hallId = data['hall_id'] as int?;
        final startTime = DateTime.tryParse(data['start_time'] ?? '');
        final endTime = DateTime.tryParse(data['end_time'] ?? '');

        if (name == null ||
            teacherId == null ||
            hallId == null ||
            startTime == null ||
            endTime == null) {
          return Response(
            400,
            body: jsonEncode({'error': 'Missing or invalid fields in request.'}),
            headers: {'content-type': 'application/json'},
          );
        }

       
        final overlap = await connection.execute(
          Sql.named('''
            SELECT COUNT(*) FROM groups
            WHERE hall_id = @hallId
              AND ((start_time, end_time) OVERLAPS (@startTime, @endTime))
          '''), parameters: {
          'hallId': hallId,
          'startTime': startTime,
          'endTime': endTime,
        });

        final overlapCount = (overlap.first[0] ?? 0) as int;
        if (overlapCount > 0) {
          return Response(
            400,
            body: jsonEncode({
              'error':
                  'Time conflict: another group already scheduled in this hall.'
            }),
            headers: {'content-type': 'application/json'},
          );
        }

        await connection.execute(
          Sql.named('''
            INSERT INTO groups (name, teacher_id, hall_id, start_time, end_time)
            VALUES (@name, @teacherId, @hallId, @startTime, @endTime)
          '''), parameters: {
          'name': name,
          'teacherId': teacherId,
          'hallId': hallId,
          'startTime': startTime,
          'endTime': endTime,
        });

        print('✅ Group added: $name');
        return Response.ok(
          jsonEncode({'message': 'Group added successfully'}),
          headers: {'content-type': 'application/json'},
        );
      } catch (e, st) {
        print('❌ Error adding group: $e');
        print(st);
        return Response.internalServerError(
          body: jsonEncode({'error': e.toString()}),
          headers: {'content-type': 'application/json'},
        );
      }
    });

    return router;
  }
}

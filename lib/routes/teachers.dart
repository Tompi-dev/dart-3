import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../db/connection.dart';
import 'package:postgres/postgres.dart' show Sql;

class TeachersHandler {
  Router get router {
    final r = Router();

    // POST /groups/create
    r.post('/groups/create', (Request req) async {
      final user = req.context['user'] as Map?;
      if (user == null || user['role'] != 'teacher') {
        return Response.forbidden(
          jsonEncode({'error': 'Teacher auth required'}),
          headers: {'content-type': 'application/json'},
        );
      }

      final authHeader = req.headers['Authorization'];
      if (authHeader == null || !authHeader.startsWith('Bearer ')) {
        return Response.forbidden(
          jsonEncode({'error': 'Missing or invalid Authorization header'}),
          headers: {'content-type': 'application/json'},
        );
      }

      final body = await req.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final hallId = data['hall_id'] as int;
      final startTime = data['start_time'] as String; // ISO string
      final isAdditional = (data['is_additional'] ?? false) == true;
      final name = data['name'] as String?;
      
      final hallCheck = await connection.execute(
        Sql.named('''
    SELECT COUNT(*) FROM halls WHERE id = @hallId
  '''),
        parameters: {'hallId': hallId},
      );

      final existsHall = int.tryParse(hallCheck.first[0].toString()) ?? 0;
      if (existsHall == 0) {
        return Response(
          400,
          body: jsonEncode({'error': 'There is no such a hall'}),
          headers: {'content-type': 'application/json'},
        );
      }

      await connection.execute(
        Sql.named(
          'INSERT INTO teachers (id) VALUES (@id) ON CONFLICT (id) DO NOTHING',
        ),
        parameters: {'id': user['id']},
      );

      final conflict = await connection.execute(
        Sql.named('''
        SELECT 1 FROM groups g
        WHERE g.hall_id = @hall  AND
              tstzrange(g.start_time, g.start_time + g.duration) &&
              tstzrange(@st::timestamptz, @st::timestamptz + interval '90 minutes')
        LIMIT 1
      '''),
        parameters: {'hall': hallId, 'st': startTime},
      );
      if (conflict.isNotEmpty) {
        return Response(
          409,
          body: jsonEncode({'error': 'Hall is occupied at that time'}),
          headers: {'content-type': 'application/json'},
        );
      }

      final res = await connection.execute(
        Sql.named('''
        INSERT INTO groups (teacher_id, hall_id, start_time, is_additional, name, created_by, created_at, )
        VALUES (@tid, @hall, @st::timestamptz, @add, @name, @tid, NOW()) RETURNING id
      '''),
        parameters: {
          'tid': user['id'],
          'hall': hallId,
          'st': startTime,
          'add': isAdditional,
          'name': name ?? 'Untitled Group',
          
        },
      );

      final id = res.first[0] as int;
      return Response.ok(
        jsonEncode({'id': id}),
        headers: {'content-type': 'application/json'},
      );
    });

    // POST /groups/<id>/extra
    r.post('/groups/<id|[0-9]+>/extra', (Request req, String id) async {
      final user = req.context['user'] as Map?;
      if (user == null || user['role'] != 'teacher') {
        return Response.forbidden(
          jsonEncode({'error': 'Teacher auth required'}),
          headers: {'content-type': 'application/json'},
        );
      }

      final groupId = int.parse(id);
      final body = await req.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final newStart = data['start_time'] as String; // ISO-8601 string

      final g = await connection.execute(
        Sql.named(
          'SELECT hall_id FROM groups WHERE id = @gid AND teacher_id = @tid',
        ),
        parameters: {'gid': groupId, 'tid': user['id']},
      );
      if (g.isEmpty) {
        return Response.notFound(
          jsonEncode({'error': 'Group not found or not owned by teacher'}),
          headers: {'content-type': 'application/json'},
        );
      }

      final hallId = g.first[0] as int;

      final overlap = await connection.execute(
        Sql.named('''
      SELECT COUNT(*) FROM groups
      WHERE hall_id = @hall
        AND cancelled = FALSE
        AND ((start_time, start_time + INTERVAL '90 minutes') OVERLAPS (@st, @et))
    '''),
        parameters: {
          'hall': hallId,
          'st': DateTime.parse(newStart),
          'et': DateTime.parse(newStart).add(const Duration(minutes: 90)),
        },
      );

      final overlapCount = (overlap.first[0] ?? 0) as int;
      if (overlapCount > 0) {
        return Response(
          409,
          body: jsonEncode({'error': 'Hall is occupied at that time'}),
          headers: {'content-type': 'application/json'},
        );
      }

      await connection.execute(
        Sql.named('''
      INSERT INTO groups (teacher_id, hall_id, start_time, end_time, is_additional, created_at, created_by)
      VALUES (@tid, @hall, @st, @et, TRUE, @tid, NOW())
    '''),
        parameters: {
          'tid': user['id'],
          'hall': hallId,
          'st': DateTime.parse(newStart),
          'et': DateTime.parse(newStart).add(const Duration(minutes: 90)),
        },
      );

      return Response.ok(
        jsonEncode({'message': 'Extra lesson added successfully'}),
        headers: {'content-type': 'application/json'},
      );
    });

    // POST /groups/<id>/cancel
    r.post('/groups/<id|[0-9]+>/cancel', (Request req, String id) async {
      final user = req.context['user'] as Map?;
      if (user == null || user['role'] != 'teacher') {
        return Response.forbidden(
          jsonEncode({'error': 'Teacher auth required'}),
          headers: {'content-type': 'application/json'},
        );
      }

      final groupId = int.parse(id);
       final g = await connection.execute(
        Sql.named(
          'SELECT hall_id FROM groups WHERE id = @gid AND teacher_id = @tid',
        ),
        parameters: {'gid': groupId, 'tid': user['id']},
      );
      if (g.isEmpty) {
        return Response.notFound(
          jsonEncode({'error': 'Group not found or not owned by teacher'}),
          headers: {'content-type': 'application/json'},
        );
      }

      // тут заяка админга жберелед
      await connection.execute(
        Sql.named('''
      INSERT INTO schedule_exceptions (teacher_id, hall_id, group_id, exception_type, approved_by_admin)
      SELECT teacher_id, hall_id, id, 'cancel', FALSE
      FROM groups
      WHERE id = @gid AND teacher_id = @tid
    '''),
        parameters: {'gid': groupId, 'tid': user['id']},
      );

      return Response.ok(
        jsonEncode({
          'ok': true,
          'submitted_for_approval': true,
          'message': 'Cancellation request sent to admin for approval',
        }),
        headers: {'content-type': 'application/json'},
      );
    });

    // POST /groups/<id>/move
    r.post('/groups/<id|[0-9]+>/move', (Request req, String id) async {
      final user = req.context['user'] as Map?;
      if (user == null || user['role'] != 'teacher') {
        return Response.forbidden(
          jsonEncode({'error': 'Teacher auth required'}),
          headers: {'content-type': 'application/json'},
        );
      }
      final groupId = int.parse(id);
      final body = await req.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final newTime = data['new_time'] as String;

      // Exception request (admin approval flow)
      await connection.execute(
        Sql.named('''
        INSERT INTO schedule_exceptions (teacher_id, hall_id, group_id, exception_type, approved_by_admin, new_time)
        SELECT teacher_id, hall_id, id, 'move', FALSE, @nt::timestamptz FROM groups WHERE id = @gid AND teacher_id = @tid
      '''),

        parameters: {'gid': groupId, 'tid': user['id'], 'nt': newTime},
      );

      return Response.ok(
        jsonEncode({'ok': true, 'submitted_for_approval': true}),
        headers: {'content-type': 'application/json'},
      );
    });

    return r;
  }
}

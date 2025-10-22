import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../db/connection.dart';
import 'package:postgres/postgres.dart' show Sql;

/// AdminHandler — analytics and admin operations
class AdminHandler {
  Router get router {
    final r = Router();

    // expose both /analytics and /admin/analytics to avoid mount confusion
    r.get('/analytics', _analytics);
    

    r.get('/halls/free-slots', (Request req) async {
      final qp = req.url.queryParameters;
      final from = qp['from'];
      final to = qp['to'];
      if (from == null || to == null) {
        return Response(
          400,
          body: jsonEncode({'error': 'from and to required (ISO timestamps)'}),
          headers: {'content-type': 'application/json'},
        );
      }

      try {
        final rows = await connection.execute(
          Sql.named('''
            SELECT h.id AS hall_id, h.name AS hall_name,
                   g.id AS group_id, g.start_time AS start_time, 
               EXTRACT(EPOCH FROM g.duration) / 60 AS duration_min

                   
            FROM halls h
            LEFT JOIN groups g
              ON g.hall_id = h.id
              AND g.cancelled = FALSE
              AND tstzrange(g.start_time, g.start_time + (g.duration || ' minutes')::interval) &&
                  tstzrange(@from::timestamptz, @to::timestamptz)
            ORDER BY h.id, g.start_time
          '''),
          parameters: {'from': from, 'to': to},
        );

          
        final list = rows.map((r) {
          return {
            'hall': {'id': r[0], 'name': r[1]},
            'group_id': r[2],
            'busy_start': r[3]?.toString(),
            'busy_duration': r[4],
          };
        }).toList();

        return Response.ok(jsonEncode({'busy': list}),
            headers: {'content-type': 'application/json'});
      } catch (e) {
        return Response.internalServerError(
            body: jsonEncode({'error': e.toString()}),
            headers: {'content-type': 'application/json'});
      }
    });

    r.post('/exceptions/approve', (Request req) async {
      try {
        final body = await req.readAsString();
        final data = jsonDecode(body) as Map<String, dynamic>;
        final exceptionId = data['exception_id'] as int?;
        final approve = (data['approve'] ?? true) == true;

        if (exceptionId == null) {
          return Response(400,
              body: jsonEncode({'error': 'exception_id required'}),
              headers: {'content-type': 'application/json'});
        }

        // Check exception existence and approval state
        final exRows = await connection.execute(
          Sql.named('SELECT id, group_id, exception_type, new_time, approved_by_admin FROM schedule_exceptions WHERE id = @id'),
          parameters: {'id': exceptionId},
        );

        if (exRows.isEmpty) {
          return Response.notFound(
              jsonEncode({'error': 'Exception not found'}),
              headers: {'content-type': 'application/json'});
        }

        final exRow = exRows.first;
        final groupId = exRow[1] as int?;
        final type = exRow[2] as String?;
        final newTime = exRow[3];
        final approvedAlready = exRow[4] == true;

        if (approvedAlready) {
          return Response(409,
              body: jsonEncode({'error': 'Exception already approved'}),
              headers: {'content-type': 'application/json'});
        }

        if (!approve) {
          await connection.execute(
            Sql.named('UPDATE schedule_exceptions SET approved_by_admin = FALSE WHERE id = @id'),
            parameters: {'id': exceptionId},
          );
          await connection.execute(
            Sql.named(
                "INSERT INTO logs (action, details) VALUES ('exception_review', @d)"),
            parameters: {
              'd': jsonEncode(
                  {'exception_id': exceptionId, 'approved': false})
            },
          );
          return Response.ok(
              jsonEncode({'ok': true, 'approved': false}),
              headers: {'content-type': 'application/json'});
        }

        if (type == 'move' && newTime != null && groupId != null) {
          await connection.execute(
            Sql.named('UPDATE groups SET start_time = @nt WHERE id = @gid'),
            parameters: {'nt': newTime, 'gid': groupId},
          );
        } else if (type == 'cancel' && groupId != null) {
          await connection.execute(
            Sql.named('UPDATE groups SET cancelled = TRUE WHERE id = @gid'),
            parameters: {'gid': groupId},
          );
        }

        await connection.execute(
          Sql.named(
              'UPDATE schedule_exceptions SET approved_by_admin = TRUE WHERE id = @id'),
          parameters: {'id': exceptionId},
        );

        await connection.execute(
          Sql.named(
              "INSERT INTO logs (action, details) VALUES ('exception_approved', @d)"),
          parameters: {
            'd': jsonEncode(
                {'exception_id': exceptionId, 'approved': true})
          },
        );

        return Response.ok(jsonEncode({'ok': true, 'approved': true}),
            headers: {'content-type': 'application/json'});
      } catch (e) {
        return Response.internalServerError(
            body: jsonEncode({'error': e.toString()}),
            headers: {'content-type': 'application/json'});
      }
    });

    r.post('/teachers/<id|[0-9]+>/limit', (Request req, String id) async {
      try {
        final teacherId = int.parse(id);

        final exists = await connection.execute(
          Sql.named('SELECT 1 FROM teachers WHERE id = @id LIMIT 1'),
          parameters: {'id': teacherId},
        );
        if (exists.isEmpty) {
          return Response.notFound(
              jsonEncode({'error': 'Teacher not found'}),
              headers: {'content-type': 'application/json'});
        }

        await connection.execute(
          Sql.named('UPDATE teachers SET is_frozen = TRUE WHERE id = @id'),
          parameters: {'id': teacherId},
        );

        await connection.execute(
          Sql.named(
              "INSERT INTO logs (action, details) VALUES ('teacher_limit', @d)"),
          parameters: {
            'd': jsonEncode(
                {'teacher_id': teacherId, 'is_frozen': true})
          },
        );

        return Response.ok(
            jsonEncode(
                {'ok': true, 'teacher_id': teacherId, 'is_frozen': true}),
            headers: {'content-type': 'application/json'});
      } catch (e) {
        return Response.internalServerError(
            body: jsonEncode({'error': e.toString()}),
            headers: {'content-type': 'application/json'});
      }
    });

    r.post('/groups/<id|[0-9]+>/add-student', (Request req, String id) async {
      try {
        final body = await req.readAsString();
        final data = jsonDecode(body) as Map<String, dynamic>;
        final studentId = data['student_id'] as int?;
        final isTrial = (data['is_trial'] ?? false) == true;

        if (studentId == null) {
          return Response(400,
              body: jsonEncode({'error': 'student_id required'}),
              headers: {'content-type': 'application/json'});
        }

        final gid = int.parse(id);

        await connection.execute(
          Sql.named('''
            INSERT INTO users (id, email, full_name, password_hash, role)
            SELECT @id, ('student_' || @id::text || '@local'),
                   ('Student ' || @id::text), '', 'student'
            WHERE NOT EXISTS (SELECT 1 FROM users WHERE id = @id)
          '''),
          parameters: {'id': studentId},
        );

        await connection.execute(
          Sql.named(
              'INSERT INTO students (id) VALUES (@id) ON CONFLICT (id) DO NOTHING'),
          parameters: {'id': studentId},
        );

        await connection.execute(
          Sql.named(
              'INSERT INTO group_students (group_id, student_id, is_trial) VALUES (@gid, @sid, @trial) ON CONFLICT DO NOTHING'),
          parameters: {'gid': gid, 'sid': studentId, 'trial': isTrial},
        );

        await connection.execute(
          Sql.named(
              "INSERT INTO logs (action, details) VALUES ('admin_add_student', @d)"),
          parameters: {
            'd': jsonEncode({
              'group_id': gid,
              'student_id': studentId,
              'is_trial': isTrial
            })
          },
        );

        return Response.ok(jsonEncode({'ok': true}),
            headers: {'content-type': 'application/json'});
      } catch (e) {
        return Response.internalServerError(
            body: jsonEncode({'error': e.toString()}),
            headers: {'content-type': 'application/json'});
      }
    });

    return r;
  }

  Future<Response> _analytics(Request req) async {
    try {
      final hallsRows = await connection.execute(
        Sql.named('''
          SELECT h.name, COUNT(*)::int AS classes
          FROM groups g
          JOIN halls h ON h.id = g.hall_id
          WHERE g.cancelled = FALSE
          GROUP BY h.name
          ORDER BY h.name
        '''),
      );

      final teachersRows = await connection.execute(
        Sql.named('''
          SELECT u.name, COUNT(*)::int AS classes
          FROM groups g
          JOIN teachers t ON t.id = g.teacher_id
          JOIN users u ON u.id = t.id
          WHERE g.cancelled = FALSE
          GROUP BY u.name
          ORDER BY u.name
        '''),
      );

      final byHall = hallsRows.map((r) => {'hall': r[0], 'classes': r[1]}).toList();
      final byTeacher = teachersRows.map((r) => {'teacher': r[0], 'classes': r[1]}).toList();

      return Response.ok(jsonEncode({'by_hall': byHall, 'by_teacher': byTeacher}),
          headers: {'content-type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
          body: jsonEncode({'error': e.toString()}),
          headers: {'content-type': 'application/json'});
    }
  }
}
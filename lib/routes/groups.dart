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

    // 🧠 Проверка — нет ли группы с таким же именем
    final existing = await connection.execute(
      Sql.named('SELECT id FROM groups WHERE name = @name'),
      parameters: {'name': name},
    );
    if (existing.isNotEmpty) {
      return Response(
        400,
        body: jsonEncode({'error': 'Group with this name already exists'}),
        headers: {'content-type': 'application/json'},
      );
    }

    // 🕒 Проверка пересечения времени в зале
    final overlap = await connection.execute(
      Sql.named('''
        SELECT COUNT(*) FROM groups
        WHERE hall_id = @hallId
          AND ((start_time, end_time) OVERLAPS (@startTime, @endTime))
      '''),
      parameters: {
        'hallId': hallId,
        'startTime': startTime,
        'endTime': endTime,
      },
    );

    final overlapCount = (overlap.first[0] ?? 0) as int;
    if (overlapCount > 0) {
      return Response(
        400,
        body: jsonEncode({
          'error': 'Time conflict: another group already scheduled in this hall.'
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    // ✅ Добавление новой группы (id сгенерируется автоматически)
    await connection.execute(
      Sql.named('''
        INSERT INTO groups (name, teacher_id, hall_id, start_time, end_time)
        VALUES (@name, @teacherId, @hallId, @startTime, @endTime)
      '''),
      parameters: {
        'name': name,
        'teacherId': teacherId,
        'hallId': hallId,
        'startTime': startTime,
        'endTime': endTime,
      },
    );

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



// ===== POST /groups/<id>/join =====
router.add('POST', '/groups/<id>/join', (Request req, String id) async {
  
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

  
  final role = authData['role'];
  if (role != 'student') {
    return Response.forbidden(
      jsonEncode({'error': 'Access denied. Only students can join groups.'}),
      headers: {'content-type': 'application/json'},
    );
  }

  try {
    final body = await req.readAsString();
    final data = jsonDecode(body) as Map<String, dynamic>;
    final studentId = data['student_id'] as int?;

    if (studentId == null) {
      return Response(
        400,
        body: jsonEncode({'error': 'Missing student_id in request body'}),
        headers: {'content-type': 'application/json'},
      );
    }

    final groupId = int.tryParse(id);
    if (groupId == null) {
      return Response(
        400,
        body: jsonEncode({'error': 'Invalid group ID'}),
        headers: {'content-type': 'application/json'},
      );
    }

 
    final check = await connection.execute(
      Sql.named('''
        SELECT
          (SELECT COUNT(*) FROM students WHERE id = @studentId) AS student_exists,
          (SELECT COUNT(*) FROM groups WHERE id = @groupId) AS group_exists
      '''),
      parameters: {'studentId': studentId, 'groupId': groupId},
    );

    final studentExists = (check.first[0] ?? 0) as int;
    final groupExists = (check.first[1] ?? 0) as int;

    if (studentExists == 0) {
      return Response(
        404,
        body: jsonEncode({'error': 'Student not found'}),
        headers: {'content-type': 'application/json'},
      );
    }
    if (groupExists == 0) {
      return Response(
        404,
        body: jsonEncode({'error': 'Group not found'}),
        headers: {'content-type': 'application/json'},
      );
    }

 
    final exists = await connection.execute(
      Sql.named('''
        SELECT COUNT(*) FROM group_students
        WHERE student_id = @studentId AND group_id = @groupId
      '''),
      parameters: {'studentId': studentId, 'groupId': groupId},
    );

    final existsCount = (exists.first[0] ?? 0) as int;
    if (existsCount > 0) {
      return Response(
        400,
        body: jsonEncode({'error': 'Student already joined this group'}),
        headers: {'content-type': 'application/json'},
      );
    }


    final conflict = await connection.execute(
      Sql.named('''
        SELECT COUNT(*)
        FROM group_students gs
        JOIN groups g ON gs.group_id = g.id
        JOIN groups target ON target.id = @groupId
        WHERE gs.student_id = @studentId
          AND (g.start_time, g.end_time) OVERLAPS (target.start_time, target.end_time)
      '''),
      parameters: {'studentId': studentId, 'groupId': groupId},
    );

    final conflictCount = (conflict.first[0] ?? 0) as int;
    if (conflictCount > 0) {
      return Response(
        400,
        body: jsonEncode({
          'error': 'Schedule conflict: student already has a class at this time.'
        }),
        headers: {'content-type': 'application/json'},
      );
    }

  
    await connection.execute(
      Sql.named('''
        INSERT INTO group_students (group_id, student_id, is_trial)
        VALUES (@groupId, @studentId, FALSE)
      '''),
      parameters: {'groupId': groupId, 'studentId': studentId},
    );

    print('✅ Student $studentId joined group $groupId');
    return Response.ok(
      jsonEncode({'message': 'Student joined group successfully'}),
      headers: {'content-type': 'application/json'},
    );
  } catch (e, st) {
    print('❌ Error joining group: $e');
    print(st);
    return Response.internalServerError(body: e.toString());
  }
});


// ===== POST /groups/<id>/join-trial =====
router.add('POST', '/groups/<id>/join-trial', (Request req, String id) async {

  final authHeader = req.headers['Authorization'];
  if (authHeader == null || !authHeader.startsWith('Bearer ')) {
    return Response.forbidden(
      jsonEncode({'error': 'Missing or invalid Authorization header'}),
      headers: {'content-type': 'application/json'},
    );
  }

  final token = authHeader.substring(7).trim();
  final authData = verifyJwt(token) as Map<String, dynamic>?;
  if (authData == null) {
    return Response.forbidden(
      jsonEncode({'error': 'Invalid or expired token'}),
      headers: {'content-type': 'application/json'},
    );
  }


  final role = authData['role'];
  if (role != 'student') {
    return Response.forbidden(
      jsonEncode({'error': 'Access denied. Only students can join trials.'}),
      headers: {'content-type': 'application/json'},
    );
  }

  try {
    final body = await req.readAsString();
    final data = jsonDecode(body) as Map<String, dynamic>;
    final studentId = data['student_id'] as int?;
    final groupId = int.tryParse(id);

    if (studentId == null || groupId == null) {
      return Response(
        400,
        body: jsonEncode({'error': 'Missing or invalid student_id/group_id'}),
        headers: {'content-type': 'application/json'},
      );
    }

    final check = await connection.execute(
      Sql.named('''
        SELECT
          (SELECT COUNT(*) FROM students WHERE id = @studentId) AS student_exists,
          (SELECT COUNT(*) FROM groups WHERE id = @groupId) AS group_exists
      '''),
      parameters: {'studentId': studentId, 'groupId': groupId},
    );

    final studentExists = (check.first[0] as int? ?? 0);
    final groupExists = (check.first[1] as int? ?? 0);

    if (studentExists == 0 || groupExists == 0) {
      return Response(
        404,
        body: jsonEncode({'error': 'Student or Group not found'}),
        headers: {'content-type': 'application/json'},
      );
    }

   
    final exists = await connection.execute(
      Sql.named('SELECT COUNT(*) FROM group_students WHERE student_id = @studentId AND group_id = @groupId'),
      parameters: {'studentId': studentId, 'groupId': groupId},
    );
    final existsCount = (exists.first[0] as int? ?? 0);
    if (existsCount > 0) {
      return Response(
        400,
        body: jsonEncode({'error': 'Student already joined this group'}),
        headers: {'content-type': 'application/json'},
      );
    }

  
    final conflict = await connection.execute(
      Sql.named('''
        SELECT COUNT(*)
        FROM group_students gs
        JOIN groups g ON gs.group_id = g.id
        JOIN groups target ON target.id = @groupId
        WHERE gs.student_id = @studentId
          AND (g.start_time, g.end_time) OVERLAPS (target.start_time, target.end_time)
      '''),
      parameters: {'studentId': studentId, 'groupId': groupId},
    );
    final conflictCount = (conflict.first[0] as int? ?? 0);
    if (conflictCount > 0) {
      return Response(
        400,
        body: jsonEncode({'error': 'Schedule conflict detected'}),
        headers: {'content-type': 'application/json'},
      );
    }

    await connection.execute(
      Sql.named('INSERT INTO group_students (group_id, student_id, is_trial) VALUES (@groupId, @studentId, TRUE)'),
      parameters: {'groupId': groupId, 'studentId': studentId},
    );

    print('🧪 Student $studentId joined group $groupId (trial)');
    return Response.ok(
      jsonEncode({'message': 'Student joined trial lesson successfully'}),
      headers: {'content-type': 'application/json'},
    );
  } catch (e, st) {
    print('❌ Error joining trial: $e');
    print(st);
    return Response.internalServerError(body: e.toString());
  }
});


// ===== GET /group_students =====
router.add('GET', '/group_students', (Request req) async {

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


  final role = authData['role'];
  if (role != 'teacher' && role != 'admin') {
    return Response.forbidden(
      jsonEncode({'error': 'Access denied. Teachers or Admins only.'}),
      headers: {'content-type': 'application/json'},
    );
  }

  try {
    final result = await connection.execute(
      Sql.named('''
        SELECT gs.id, gs.group_id, g.name AS group_name,
               gs.student_id, s.id AS student_ref, u.name AS student_name,
               gs.is_trial
        FROM group_students gs
        JOIN groups g ON gs.group_id = g.id
        JOIN students s ON gs.student_id = s.id
        JOIN users u ON s.user_id = u.id
        ORDER BY gs.group_id, gs.student_id;
      '''),
    );

    final data = result
        .map((row) => {
              'id': row[0],
              'group_id': row[1],
              'group_name': row[2],
              'student_id': row[3],
              'student_name': row[5],
              'is_trial': row[6],
            })
        .toList();

    return Response.ok(
      jsonEncode(data),
      headers: {'content-type': 'application/json'},
    );
  } catch (e, st) {
    print('❌ Error fetching group_students: $e');
    print(st);
    return Response.internalServerError(
      body: jsonEncode({'error': 'Database error'}),
      headers: {'content-type': 'application/json'},
    );
  }
});


    return router;
  }
}

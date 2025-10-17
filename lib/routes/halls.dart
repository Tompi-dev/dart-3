import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../db/connection.dart';
import 'package:postgres/postgres.dart' show Sql;

class HallsHandler {
  Router get router {
    final r = Router();

    // GET /halls
    r.get('/halls', (Request req) async {
      final rows = await connection.execute(Sql.named('SELECT id, name, location, capacity FROM halls ORDER BY id'));
      final list = rows.map((row) => {
            'id': row[0],
            'name': row[1],
            'location': row[2],
            'capacity': row[3],
          }).toList();
      return Response.ok(jsonEncode({'halls': list}), headers: {'content-type': 'application/json'});
    });

    // GET /halls/<id>
    r.get('/halls/<id|[0-9]+>', (Request req, String id) async {
      final hid = int.parse(id);
      final rows = await connection.execute(Sql.named('SELECT id, name, location, capacity FROM halls WHERE id = @id LIMIT 1'), parameters: {'id': hid});
      if (rows.isEmpty) return Response.notFound(jsonEncode({'error': 'Hall not found'}), headers: {'content-type': 'application/json'});
      final row = rows.first;
      return Response.ok(jsonEncode({
        'hall': {'id': row[0], 'name': row[1], 'location': row[2], 'capacity': row[3]}
      }), headers: {'content-type': 'application/json'});
    });

    // GET /halls/<id>/schedule?from=...&to=...
    r.get('/halls/<id|[0-9]+>/schedule', (Request req, String id) async {
      final qp = req.url.queryParameters;
      final from = qp['from'];
      final to = qp['to'];
      if (from == null || to == null) {
        return Response(400, body: jsonEncode({'error': 'from and to required (ISO timestamps)'}), headers: {'content-type': 'application/json'});
      }
      final hid = int.parse(id);

      // select schedule entries overlapping the interval
      final rows = await connection.execute(Sql.named('''
        SELECT g.id, g.name, g.start_time, g.end_time, g.is_additional, g.teacher_id
        FROM groups g
        WHERE g.hall_id = @hid
          AND g.cancelled = FALSE
          AND tstzrange(g.start_time, g.end_time) && tstzrange(@from::timestamptz, @to::timestamptz)
        ORDER BY g.start_time
      '''), parameters: {'hid': hid, 'from': from, 'to': to});

      final list = rows.map((r) => {
            'group_id': r[0],
            'name': r[1],
            'start_time': r[2]?.toString(),
            'end_time': r[3]?.toString(),
            'is_additional': r[4],
            'teacher_id': r[5],
          }).toList();

      return Response.ok(jsonEncode({'hall_id': hid, 'busy': list}), headers: {'content-type': 'application/json'});
    });

    // POST /halls  (admin)
    r.post('/halls', (Request req) async {
      final user = req.context['user'] as Map?;
      if (user == null || user['role'] != 'admin') {
        return Response.forbidden(jsonEncode({'error': 'Admin auth required'}), headers: {'content-type': 'application/json'});
      }

      final body = await req.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final name = (data['name'] as String?)?.trim();
      final location = (data['location'] as String?)?.trim();
      final capacity = data['capacity'] is int ? data['capacity'] as int : (data['capacity'] != null ? int.tryParse(data['capacity'].toString()) : null);

      if (name == null || name.isEmpty) return Response(400, body: jsonEncode({'error': 'name required'}), headers: {'content-type': 'application/json'});

      final res = await connection.execute(Sql.named('INSERT INTO halls (name, location, capacity) VALUES (@name, @loc, @cap) RETURNING id'), parameters: {'name': name, 'loc': location, 'cap': capacity});
      final id = res.isNotEmpty ? res.first[0] as int : null;

      await connection.execute(Sql.named("INSERT INTO logs (action, details) VALUES ('create_hall', @d)"), parameters: {'d': jsonEncode({'user': user['id'], 'hall_id': id, 'name': name})});

      return Response.ok(jsonEncode({'id': id}), headers: {'content-type': 'application/json'});
    });

    // PUT /halls/<id> (admin)
    r.put('/halls/<id|[0-9]+>', (Request req, String id) async {
      final user = req.context['user'] as Map?;
      if (user == null || user['role'] != 'admin') {
        return Response.forbidden(jsonEncode({'error': 'Admin auth required'}), headers: {'content-type': 'application/json'});
      }
      final hid = int.parse(id);
      final body = await req.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final name = (data['name'] as String?)?.trim();
      final location = (data['location'] as String?)?.trim();
      final capacity = data['capacity'] is int ? data['capacity'] as int : (data['capacity'] != null ? int.tryParse(data['capacity'].toString()) : null);

      if (name == null && location == null && capacity == null) return Response(400, body: jsonEncode({'error': 'nothing to update'}), headers: {'content-type': 'application/json'});

      final updates = <String>[];
      final params = <String, dynamic>{'id': hid};
      if (name != null) { updates.add('name = @name'); params['name'] = name; }
      if (location != null) { updates.add('location = @loc'); params['loc'] = location; }
      if (capacity != null) { updates.add('capacity = @cap'); params['cap'] = capacity; }

      final setClause = updates.join(', ');
      final updated = await connection.execute(Sql.named('UPDATE halls SET $setClause WHERE id = @id RETURNING id'), parameters: params);
      if (updated.isEmpty) return Response.notFound(jsonEncode({'error': 'Hall not found'}), headers: {'content-type': 'application/json'});

      await connection.execute(Sql.named("INSERT INTO logs (action, details) VALUES ('update_hall', @d)"), parameters: {'d': jsonEncode({'user': user['id'], 'hall_id': hid, 'changes': data})});
      return Response.ok(jsonEncode({'ok': true, 'hall_id': hid}), headers: {'content-type': 'application/json'});
    });

    // DELETE /halls/<id> (admin)
    r.delete('/halls/<id|[0-9]+>', (Request req, String id) async {
      final user = req.context['user'] as Map?;
      if (user == null || user['role'] != 'admin') {
        return Response.forbidden(jsonEncode({'error': 'Admin auth required'}), headers: {'content-type': 'application/json'});
      }
      final hid = int.parse(id);

      final deps = await connection.execute(Sql.named('SELECT 1 FROM groups WHERE hall_id = @id AND cancelled = FALSE LIMIT 1'), parameters: {'id': hid});
      if (deps.isNotEmpty) return Response(409, body: jsonEncode({'error': 'Hall has active groups'}), headers: {'content-type': 'application/json'});

      final res = await connection.execute(Sql.named('DELETE FROM halls WHERE id = @id RETURNING id'), parameters: {'id': hid});
      if (res.isEmpty) return Response.notFound(jsonEncode({'error': 'Hall not found'}), headers: {'content-type': 'application/json'});

      await connection.execute(Sql.named("INSERT INTO logs (action, details) VALUES ('delete_hall', @d)"), parameters: {'d': jsonEncode({'user': user['id'], 'hall_id': hid})});
      return Response.ok(jsonEncode({'ok': true, 'deleted': true}), headers: {'content-type': 'application/json'});
    });

    return r;
  }
}
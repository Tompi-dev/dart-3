

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'db/connection.dart';
import 'routes/auth.dart';
import 'routes/groups.dart';
import 'middleware/drugoi.dart';
import 'middleware/role_guard.dart';

Future<void> main() async {
  await connectToDatabase();


  final router = Cascade()
      .add(AuthRoute().router)
      .add(GroupsRoute().router)
      .handler;

 
  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(jwtAuthorization())
      .addHandler(router);

  final server = await io.serve(handler, 'localhost', 8080);
  print('✅ Server running on http://localhost:${server.port}');
}

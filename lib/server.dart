import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'db/connection.dart';
import 'routes/auth.dart';
import 'routes/students.dart';
import 'routes/teachers.dart';
import 'routes/admin.dart';
import 'middleware/role_guard.dart';

Future<void> main() async {
  await connectToDatabase();
  
  final router = Cascade()
      .add(AuthRoute().router)
      .add(StudentsHandler().router)
      .add(TeachersHandler().router)
      .add(AdminHandler().router)
      .handler;

  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(roleGuard())
      .addHandler(router);

  final server = await io.serve(handler, 'localhost', 8080);
  print('✅ Server running on http://localhost:${server.port}');
}

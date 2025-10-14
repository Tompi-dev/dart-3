import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'jwt_utils.dart'; // for verifyJwt()


Middleware roleGuard() {
  return (Handler innerHandler) {
    return (Request req) async {
      // Skip auth for public routes like /auth/login or /auth/register
      if (req.url.path.startsWith('auth')) {
        return innerHandler(req);
      }

      final authHeader = req.headers['Authorization'] ?? req.headers['authorization'];
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

      // ✅ Attach decoded payload (id, role, etc.) to request context
      final updatedRequest = req.change(context: {'user': authData});
      return innerHandler(updatedRequest);
    };
  };
}

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import '../env.dart';

final _secretKey = Env.require("JWT_SECRET");


Map<String, dynamic>? verifyJwt(String token) {
  try {
    final jwt = JWT.verify(token, SecretKey(_secretKey));
    final payload = jwt.payload as Map<String, dynamic>; 

    final exp = payload['exp'];
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    if (exp != null && exp is int && exp < now) {
      print(' Token expired');
      return null;
    }

    return payload;
  } catch (e) {
    print(' JWT verification failed: $e');
    return null;
  }
}


String generateJwt(int userId, String role) {
  final jwt = JWT({
    'id': userId,
    'role': role,
    'exp': DateTime.now()
        .add(const Duration(hours: 2))
        .millisecondsSinceEpoch ~/ 1000,
  });

  return jwt.sign(SecretKey(_secretKey));
  }

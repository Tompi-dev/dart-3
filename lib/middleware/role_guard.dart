
import 'dart:convert';
import 'package:jaguar_jwt/jaguar_jwt.dart';
import '../env.dart';
final _jwtSecret = Env.require("JWT_SECRET"); 


Map<String, dynamic>? verifyJwt(String token) {
  try {
  final decClaimSet = verifyJwtHS256Signature(token, _jwtSecret);
  final payload = decClaimSet.toJson(); 

  final exp = payload['exp'];
  

    
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (exp != null && exp < now) return null;

    return payload;
  } catch (e) {
    print('❌ JWT verification failed: $e');
    return null;
  }
}

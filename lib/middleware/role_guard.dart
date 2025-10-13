
import 'dart:convert';
import 'package:jaguar_jwt/jaguar_jwt.dart';

const _jwtSecret = 'super_secret_key_123'; 


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

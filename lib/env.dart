import 'package:dotenv/dotenv.dart' as dotenv;

class Env {
  static final dotenv.DotEnv _env =
      dotenv.DotEnv(includePlatformEnvironment: true)..load();

 
  static String? get(String key) => _env[key];

  
  static String require(String key) {
    final value = get(key);
    if (value == null || value.isEmpty) {
      throw Exception(' Missing environment variable: $key');
    }
    return value;
  }
}

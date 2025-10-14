import 'package:postgres/postgres.dart';
import '../env.dart';

late Connection connection;

Future<void> connectToDatabase() async {
  final host = Env.require('DB_HOST');
  final port = int.parse(Env.require('DB_PORT'));
  final dbName = Env.require('DB_NAME');
  final user = Env.require('DB_USER');
  final password = Env.require('DB_PASSWORD');

  connection = await Connection.open(
    Endpoint(
      host: host,
      port: port,
      database: dbName,
      username: user,
      password: password,
    ),
    settings: const ConnectionSettings(sslMode: SslMode.disable),
  );

  print('✅ Connected to PostgreSQL successfully!');
}

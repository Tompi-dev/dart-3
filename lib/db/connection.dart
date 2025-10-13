import 'package:postgres/postgres.dart';

late Connection connection;

Future<void> connectToDatabase() async {
  connection = await Connection.open(
    Endpoint(
      host: 'localhost',       
      port: 5432,               
      database: 'nomad_db',
      username: 'postgres',
      password: 'admin',
    ),
    settings: const ConnectionSettings(sslMode: SslMode.disable),
  );

  print('✅ Connected to PostgreSQL successfully!');
}

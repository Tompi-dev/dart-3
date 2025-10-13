import 'db/connection.dart';

void main() async {
  await connectToDatabase();

  final result = await connection.execute('SELECT NOW()');
  print(result.first);
}

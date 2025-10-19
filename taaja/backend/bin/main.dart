import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:mysql1/mysql1.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_router/shelf_router.dart';

// Database settings
const dbHost = '127.0.0.1';
const dbPort = 3300; // change to 3306 if that's your default
const dbUser = 'root';
const dbPassword = 'root';
const dbName = 'flutter_database';

Future<MySqlConnection> getConnection() {
  final settings = ConnectionSettings(
    host: dbHost,
    port: dbPort,
    user: dbUser,
    password: dbPassword,
    db: dbName,
  );
  return MySqlConnection.connect(settings);
}

String hashPassword(String password) {
  final bytes = utf8.encode(password);
  final digest = sha256.convert(bytes);
  return digest.toString();
}

// CORS Middleware
Middleware corsHeaders() {
  return (Handler innerHandler) {
    return (Request request) async {
      if (request.method == 'OPTIONS') {
        return Response.ok('', headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
          'Access-Control-Allow-Headers': 'Origin, Content-Type, Accept',
        });
      }

      final response = await innerHandler(request);
      return response.change(headers: {
        ...response.headers,
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Origin, Content-Type, Accept',
      });
    };
  };
}

void main() async {
  final router = Router();

  router.get('/', (Request req) => Response.ok('Dart server running'));

  // LOGIN ROUTE
  router.post('/login', (Request request) async {
    final body = await request.readAsString();
    final data = jsonDecode(body);
    final username = data['username']?.toString().trim() ?? '';
    final password = data['password']?.toString() ?? '';

    if (username.isEmpty || password.isEmpty) {
      return Response(400,
          body: jsonEncode({'error': 'Missing fields'}),
          headers: {'Content-Type': 'application/json'});
    }

    final hashed = hashPassword(password);
    final conn = await getConnection();
    final results = await conn.query(
      'SELECT id, username FROM users WHERE username = ? AND password_hash = ?',
      [username, hashed],
    );
    await conn.close();

    if (results.isNotEmpty) {
      final row = results.first;
      final user = {'id': row[0], 'username': row[1]};
      return Response.ok(jsonEncode({'status': 'ok', 'user': user}),
          headers: {'Content-Type': 'application/json'});
    } else {
      return Response(401,
          body: jsonEncode({'error': 'Invalid credentials'}),
          headers: {'Content-Type': 'application/json'});
    }
  });

  // REGISTER ROUTE
  router.post('/register', (Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body);
      final username = data['username']?.toString().trim() ?? '';
      final password = data['password']?.toString() ?? '';

      if (username.isEmpty || password.isEmpty) {
        return Response(400,
            body: jsonEncode({'error': 'Missing fields'}),
            headers: {'Content-Type': 'application/json'});
      }

      final hashed = hashPassword(password);
      final conn = await getConnection();

      final existing = await conn.query(
        'SELECT id FROM users WHERE username = ?',
        [username],
      );

      if (existing.isNotEmpty) {
        await conn.close();
        return Response(409,
            body: jsonEncode({'status': 'error', 'error': 'Username already exists'}),
            headers: {'Content-Type': 'application/json'});
      }

      await conn.query(
        'INSERT INTO users (username, password_hash) VALUES (?, ?)',
        [username, hashed],
      );

      await conn.close();

      return Response.ok(
        jsonEncode({'status': 'ok', 'message': 'User registered successfully'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      print('Register Error: $e');
      return Response.internalServerError(
        body: jsonEncode({'status': 'error', 'error': 'Server error'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  // Handle unknown routes
  router.all('/<ignored|.*>', (Request request) {
    return Response.notFound(jsonEncode({'error': 'Route not found'}), headers: {
      'Content-Type': 'application/json'
    });
  });

  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(corsHeaders())
      .addHandler(router);

  final server = await serve(handler, InternetAddress.anyIPv4, 8080);
  print('✅ Server running on http://${server.address.address}:${server.port}');
}

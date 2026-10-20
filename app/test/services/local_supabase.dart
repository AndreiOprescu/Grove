import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:grove/sync/sync.dart';

import '../sync/fake_supabase.dart';

/// A small web server on this computer (127.0.0.1) that answers like the
/// parts of Supabase that Grove uses: the login with an email code, the two
/// database functions and the file store. The rules of the rows are the
/// ones of [FakeSupabase]. Nothing leaves this computer.
class LocalSupabase {
  LocalSupabase._(this._server, this.rows);

  static Future<LocalSupabase> start(RemoteSchema schema) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final local = LocalSupabase._(server, FakeSupabase(schema, userId: null));
    server.listen(local._handle);
    return local;
  }

  final HttpServer _server;
  final FakeSupabase rows;

  String get url => 'http://127.0.0.1:${_server.port}';

  /// The code that is in every email.
  String code = '123456';

  /// The addresses an email went to.
  final sent = <String>[];

  /// Set to answer the next "send the email" with "too many".
  bool tooMany = false;

  /// True: the server cuts every connection with no answer, as a network
  /// that is down.
  bool down = false;

  /// "METHOD path" of every request, oldest first.
  final requests = <String>[];

  /// The tokens that are good, with the person they are of.
  final _sessions = <String, String>{};
  var _count = 0;

  static String userIdOf(String email) => 'id-of-${email.toLowerCase()}';

  Future<void> stop() => _server.close(force: true);

  String _token(String user) {
    String part(Object o) =>
        base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
    final exp = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
    _count += 1;
    final token =
        '${part({'alg': 'HS256', 'typ': 'JWT'})}.'
        '${part({'sub': user, 'exp': exp, 'role': 'authenticated', 'n': _count})}'
        '.sig';
    _sessions[token] = user;
    return token;
  }

  String? _user(HttpRequest request) {
    final header = request.headers.value(HttpHeaders.authorizationHeader);
    if (header == null || !header.startsWith('Bearer ')) return null;
    return _sessions[header.substring(7)];
  }

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;
    requests.add('${request.method} $path');
    if (down) {
      (await request.response.detachSocket(writeHeaders: false)).destroy();
      return;
    }
    final body = await request
        .fold<BytesBuilder>(BytesBuilder(), (b, chunk) => b..add(chunk))
        .then((b) => b.takeBytes());
    try {
      if (path.startsWith('/auth/v1/')) {
        _auth(request, path.substring(9), body);
      } else if (path.startsWith('/rest/v1/rpc/')) {
        await _rpc(request, path.substring(13), body);
      } else if (path.startsWith('/storage/v1/object/')) {
        await _file(request, path.substring(19), body);
      } else {
        _json(request, 404, {'message': 'No such path: $path'});
      }
    } on SupabaseApiError catch (e) {
      _json(request, 400, {
        'code': e.code,
        'message': e.message,
        'details': null,
        'hint': null,
      });
    }
    await request.response.close();
  }

  void _json(HttpRequest request, int status, Object? body) {
    request.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..headers.set('x-supabase-api-version', '2024-01-01')
      ..write(jsonEncode(body));
  }

  void _auth(HttpRequest request, String call, Uint8List body) {
    final sentBody = body.isEmpty
        ? const <String, Object?>{}
        : jsonDecode(utf8.decode(body)) as Map<String, Object?>;
    switch (call) {
      case 'otp':
        if (tooMany) {
          tooMany = false;
          return _json(request, 429, {
            'code': 429,
            'error_code': 'over_email_send_rate_limit',
            'msg': 'email rate limit exceeded',
          });
        }
        sent.add(sentBody['email']! as String);
        _json(request, 200, <String, Object?>{});
      case 'verify':
        final email = sentBody['email'] as String?;
        if (email == null ||
            !sent.contains(email) ||
            sentBody['token'] != code ||
            sentBody['type'] != 'email') {
          return _json(request, 403, {
            'code': 403,
            'error_code': 'otp_expired',
            'msg': 'Token has expired or is invalid',
          });
        }
        final user = userIdOf(email);
        _json(request, 200, {
          'access_token': _token(user),
          'token_type': 'bearer',
          'expires_in': 3600,
          'refresh_token': 'refresh-$_count',
          'user': {
            'id': user,
            'aud': 'authenticated',
            'role': 'authenticated',
            'email': email,
            'app_metadata': <String, Object?>{},
            'user_metadata': <String, Object?>{},
            'created_at': '2026-10-11T00:00:00Z',
          },
        });
      case 'logout':
        final header = request.headers.value(HttpHeaders.authorizationHeader);
        if (header != null) {
          _sessions.remove(header.replaceFirst('Bearer ', ''));
        }
        request.response.statusCode = 204;
      default:
        _json(request, 404, {'msg': 'No such call: $call'});
    }
  }

  Future<void> _rpc(
    HttpRequest request,
    String function,
    Uint8List body,
  ) async {
    rows.userId = _user(request);
    final args = jsonDecode(utf8.decode(body)) as Map<String, Object?>;
    _json(request, 200, await rows.rpc(function, args));
  }

  Future<void> _file(HttpRequest request, String rest, Uint8List body) async {
    rows.userId = _user(request);
    final cut = rest.indexOf('/');
    final bucket = rest.substring(0, cut);
    final path = Uri.decodeComponent(rest.substring(cut + 1));
    if (request.method == 'GET') {
      final bytes = await rows.download(bucket, path);
      if (bytes == null) {
        return _json(request, 400, {
          'statusCode': '404',
          'error': 'not_found',
          'message': 'Object not found',
        });
      }
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.binary
        ..add(bytes);
      return;
    }
    // The package sends a form with parts, as a browser does. The file is
    // the part that has a file name.
    final file = _filePart(
      body,
      request.headers.contentType?.parameters['boundary'],
    );
    if (file == null) {
      return _json(request, 400, {
        'statusCode': '400',
        'error': 'invalid_request',
        'message': 'No file in the form',
      });
    }
    try {
      await rows.upload(
        bucket,
        path,
        file.bytes,
        contentType: file.contentType,
      );
    } on SupabaseApiError catch (e) {
      return _json(request, 403, {
        'statusCode': '403',
        'error': 'Unauthorized',
        'message': e.message,
      });
    }
    _json(request, 200, {'Key': '$bucket/$path'});
  }

  static int _find(Uint8List data, List<int> what, int from) {
    for (var i = from; i <= data.length - what.length; i++) {
      var same = true;
      for (var j = 0; j < what.length && same; j++) {
        same = data[i + j] == what[j];
      }
      if (same) return i;
    }
    return -1;
  }

  static ({Uint8List bytes, String contentType})? _filePart(
    Uint8List body,
    String? boundary,
  ) {
    if (boundary == null) return null;
    final mark = ascii.encode('--$boundary');
    const blank = [13, 10, 13, 10];
    var at = _find(body, mark, 0);
    while (at >= 0) {
      final next = _find(body, mark, at + mark.length);
      if (next < 0) return null;
      final headEnd = _find(body, blank, at);
      if (headEnd < 0 || headEnd > next) return null;
      final head = utf8.decode(body.sublist(at + mark.length, headEnd));
      if (head.contains('filename=')) {
        final type = RegExp(
          r'content-type:\s*([^\r\n;]+)',
          caseSensitive: false,
        ).firstMatch(head);
        return (
          // The part ends with a line break before the next mark.
          bytes: body.sublist(headEnd + 4, next - 2),
          contentType: type?.group(1)?.trim() ?? '',
        );
      }
      at = next;
    }
    return null;
  }
}

import 'dart:convert';

import 'package:arena_protocol/arena_protocol.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../clock.dart';
import '../rate_limit.dart';
import '../rooms/room.dart';
import '../rooms/room_manager.dart';

/// Largest accepted frame. A full move list is well under 1 KB.
const int kMaxFrameLength = 16 * 1024;

/// The identity behind a session token.
typedef SocketUser = ({String id, String displayName});

/// GET /v1/ws?token=... The token is checked before the upgrade.
Handler webSocketRoute({
  required RoomManager rooms,
  required Future<SocketUser?> Function(String token) authenticate,
  required Clock clock,
  required int messagesPerSecond,
}) {
  return (Request req) async {
    final token = req.url.queryParameters['token'];
    final user = token == null ? null : await authenticate(token);
    if (user == null) {
      return Response(
        401,
        body: jsonEncode({
          'error': {'code': ErrorCodes.unauthorized, 'message': 'bad token'},
        }),
        headers: {'content-type': 'application/json'},
      );
    }
    final handler = webSocketHandler((WebSocketChannel channel, String? _) {
      final conn = _SocketConnection(channel, user.id, user.displayName);
      final limiter = RateLimiter(
        limit: messagesPerSecond,
        window: const Duration(seconds: 1),
        clock: clock,
      );
      channel.stream.listen(
        (frame) {
          if (!limiter.allow('')) {
            conn.send(
              const ErrorMessage(
                code: ErrorCodes.rateLimited,
                message: 'too many messages',
              ),
            );
            return;
          }
          if (frame is! String || frame.length > kMaxFrameLength) {
            conn.send(
              const ErrorMessage(
                code: ErrorCodes.badRequest,
                message: 'frames must be JSON text',
              ),
            );
            return;
          }
          final ClientMessage msg;
          try {
            msg = ClientMessage.decode(frame);
          } on ProtocolException catch (e) {
            conn.send(
              ErrorMessage(
                ref: _cseqOf(frame),
                code: ErrorCodes.badRequest,
                message: e.message,
              ),
            );
            return;
          }
          rooms.handle(conn, msg);
        },
        onDone: () {
          conn.closed = true;
          rooms.disconnected(conn);
        },
        onError: (Object _) {},
        cancelOnError: false,
      );
    }, pingInterval: const Duration(seconds: 20));
    return handler(req);
  };
}

int? _cseqOf(String frame) {
  try {
    final v = jsonDecode(frame);
    if (v is Map && v['cseq'] is int) return v['cseq'] as int;
  } on FormatException {
    // No ref then.
  }
  return null;
}

class _SocketConnection extends Connection {
  _SocketConnection(this._channel, String userId, String displayName)
    : super(userId: userId, displayName: displayName);

  final WebSocketChannel _channel;
  bool closed = false;

  @override
  void send(ServerMessage message) {
    if (closed) return;
    _channel.sink.add(message.encode());
  }

  @override
  void close() {
    if (closed) return;
    closed = true;
    _channel.sink.close(4000, 'replaced by a new connection');
  }
}

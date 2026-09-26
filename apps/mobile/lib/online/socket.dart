import 'package:arena_protocol/arena_protocol.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'config.dart';

/// One open game socket. [messages] ends when the socket closes.
abstract interface class GameSocket {
  Stream<ServerMessage> get messages;
  void send(ClientMessage message);
  Future<void> close();
}

/// Opens a socket with a session token. Throws when the server cannot be
/// reached.
typedef SocketConnector = Future<GameSocket> Function(String token);

class WsGameSocket implements GameSocket {
  WsGameSocket._(this._channel);

  final WebSocketChannel _channel;

  static Future<GameSocket> connect(Uri baseUrl, String token) async {
    final uri = baseUrl
        .resolve('/v1/ws')
        .replace(
          scheme: baseUrl.scheme == 'https' ? 'wss' : 'ws',
          queryParameters: {'token': token},
        );
    final channel = WebSocketChannel.connect(uri);
    await channel.ready;
    return WsGameSocket._(channel);
  }

  @override
  late final Stream<ServerMessage> messages = _channel.stream
      .where((frame) => frame is String)
      .map((frame) {
        try {
          return ServerMessage.decode(frame as String);
        } on ProtocolException {
          return null;
        }
      })
      .where((m) => m != null && m is! UnknownServerMessage)
      .cast<ServerMessage>();

  @override
  void send(ClientMessage message) => _channel.sink.add(message.encode());

  @override
  Future<void> close() => _channel.sink.close();
}

final socketConnectorProvider = Provider<SocketConnector>(
  (ref) =>
      (token) => WsGameSocket.connect(Uri.parse(kServerUrl), token),
);

import 'dart:async';
import 'dart:io';

import 'package:arena_server/arena_server.dart';

Future<void> main() async {
  final ServerConfig config;
  try {
    config = ServerConfig.fromEnvironment(Platform.environment);
  } on ConfigException catch (e) {
    stderr.writeln(e.message);
    exit(78); // EX_CONFIG
  }
  if (config.randomSessionSecret) {
    stdout.writeln(
      'SESSION_SECRET is not set: using a random one, logins end on restart',
    );
  }
  final server = await startServer(config);
  stdout.writeln(
    'Arena server ${config.appVersion} listening on port ${server.port}',
  );
  final stop = Completer<void>();
  for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
    signal.watch().listen((_) {
      if (!stop.isCompleted) stop.complete();
    });
  }
  await stop.future;
  stdout.writeln('shutting down');
  await server.close();
  exit(0);
}

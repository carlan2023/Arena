/// The Arena game server.
///
/// Start one in process with `startServer(ServerConfig.forTests())`.
library;

export 'config.dart';
export 'src/clock.dart';
export 'src/rooms/room.dart' show Room, Seat, Connection;
export 'src/rooms/room_manager.dart'
    show RoomManager, RoomSettings, RoomException, MoveChooser;
export 'src/server.dart';
export 'src/store/live_store.dart';
export 'src/store/match_log.dart';
export 'src/store/migrations.dart'
    show serverMigrations, runMigrations, openPool;

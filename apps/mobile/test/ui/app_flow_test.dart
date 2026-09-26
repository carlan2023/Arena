import 'dart:async';

import 'package:arena/app/app.dart';
import 'package:arena/ui/game_table.dart';
import 'package:arena/ui/local_setup_screen.dart';
import 'package:arena/ui/room_screen.dart';
import 'package:arena_protocol/arena_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_engine/ludo_engine.dart';

import '../online/fakes.dart';

class App {
  App(this.tester);

  final WidgetTester tester;
  final connector = FakeConnector();
  final api = FakeApi();
  final links = StreamController<Uri>();
  final shared = <String>[];

  Future<void> start({bool loggedIn = true}) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...onlineOverrides(
            connector,
            api: api,
            session: loggedIn ? session : null,
          ),
          incomingLinksProvider.overrideWithValue(links.stream),
          shareTextProvider.overrideWithValue((t) async => shared.add(t)),
        ],
        child: const ArenaApp(),
      ),
    );
    await settle(tester);
  }

  /// Unmounts the app so its timers stop before the test ends.
  Future<void> stop() async {
    await tester.pumpWidget(const SizedBox());
    unawaited(links.close());
  }

  Future<void> receive(ServerMessage m) async {
    connector.last.receive(m);
    await settle(tester);
  }
}

void main() {
  testWidgets('phone, wrong code, right code, name, then home', (tester) async {
    final app = App(tester);
    await app.start(loggedIn: false);
    expect(find.byKey(const Key('play-friends')), findsOneWidget);
    await tester.tap(find.byKey(const Key('sign-in')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('phone')), '0772 000001');
    await tester.tap(find.byKey(const Key('login-next')));
    await settle(tester);
    expect(find.textContaining('+256772000001'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('code')), '111111');
    await tester.tap(find.byKey(const Key('login-next')));
    await settle(tester);
    expect(find.byKey(const Key('login-error')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('code')), '123456');
    await tester.tap(find.byKey(const Key('login-next')));
    await settle(tester);
    expect(app.api.calls, ['login fake:+256772000001']);
    expect(find.byKey(const Key('name')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('name')), 'Amina');
    await tester.tap(find.byKey(const Key('login-next')));
    await settle(tester);
    expect(find.text('Hello, Amina'), findsOneWidget);
    await app.stop();
  });

  testWidgets('a bad phone number is refused on the phone', (tester) async {
    final app = App(tester);
    await app.start(loggedIn: false);
    await tester.tap(find.byKey(const Key('sign-in')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('phone')), '12345');
    await tester.tap(find.byKey(const Key('login-next')));
    await settle(tester);
    expect(find.text('Enter a Ugandan mobile number'), findsOneWidget);
    await app.stop();
  });

  testWidgets('an invite link with no account opens the room as a guest', (
    tester,
  ) async {
    final app = App(tester);
    await app.start(loggedIn: false);
    app.links.add(Uri.parse('arena://r/abc234'));
    await settle(tester);
    expect(find.byKey(const Key('phone')), findsNothing);
    expect(find.byType(RoomScreen), findsOneWidget);
    expect(find.text('Room ABC234'), findsOneWidget);
    expect(app.api.calls, ['guest']);
    expect(app.connector.tokens, ['guest-tok']);
    await app.stop();
  });

  testWidgets('a guest creates a room without signing up', (tester) async {
    final app = App(tester);
    await app.start(loggedIn: false);
    await tester.tap(find.byKey(const Key('play-friends')));
    await settle(tester);
    await tester.tap(find.text('1 v 1'));
    await settle(tester);
    expect(app.api.calls, ['guest', 'create guest-tok oneVsOne 2']);
    expect(find.byType(RoomScreen), findsOneWidget);
    await app.stop();
  });

  testWidgets('a guest can still sign in with a phone for paid play', (
    tester,
  ) async {
    final app = App(tester);
    app.api.user = me;
    await app.start(loggedIn: false);
    await tester.tap(find.byKey(const Key('play-friends')));
    await settle(tester);
    await tester.tap(find.text('1 v 1'));
    await settle(tester);
    await tester.tap(find.byTooltip('Leave'));
    await settle(tester);
    expect(find.byKey(const Key('sign-in')), findsOneWidget);
    await tester.tap(find.byKey(const Key('sign-in')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('phone')), '772000001');
    await tester.tap(find.byKey(const Key('login-next')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('code')), '123456');
    await tester.tap(find.byKey(const Key('login-next')));
    await settle(tester);
    expect(find.text('Hello, Amina'), findsOneWidget);
    expect(find.byKey(const Key('sign-in')), findsNothing);
    await app.stop();
  });

  testWidgets('lobby: share the invite and start as host', (tester) async {
    final app = App(tester);
    await app.start();
    app.links.add(Uri.parse('https://arena.example/r/ABC234'));
    await settle(tester);
    await app.receive(
      lobbyState(room: lobbyRoom(players: [player(0, me), player(1, them)])),
    );
    expect(find.byKey(const Key('lobby-code')), findsOneWidget);
    expect(find.text('Amina (you)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('share')));
    expect(app.shared.single, contains('https://arena.example/r/ABC234'));

    await tester.tap(find.byKey(const Key('start-game')));
    expect(app.connector.last.sent.last, isA<StartGameMessage>());
    await app.stop();
  });

  testWidgets('game, reconnect banner, quick chat and results', (tester) async {
    final app = App(tester);
    await app.start();
    await tester.tap(find.byKey(const Key('join-code')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('room-code')), 'abc234');
    await tester.tap(find.byKey(const Key('join')));
    await settle(tester);
    expect(find.byType(RoomScreen), findsOneWidget);

    await app.receive(gameState());
    expect(find.byType(GameTable), findsOneWidget);
    await tester.tap(find.byKey(const Key('roll')));
    expect(app.connector.last.sent.last, isA<RollMessage>());

    await tester.ensureVisible(find.byKey(const Key('emote-gg')));
    await tester.tap(find.byKey(const Key('emote-gg')));
    expect((app.connector.last.sent.last as EmoteMessage).id, 'gg');
    await app.receive(const EmoteEvent(seq: 4, seat: 1, id: 'gg'));
    expect(find.text('Brian: Good game'), findsOneWidget);

    app.connector.last.drop();
    await tester.pump();
    expect(find.byKey(const Key('reconnecting')), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await app.receive(gameState(seq: 5));
    expect(find.byKey(const Key('reconnecting')), findsNothing);

    await app.receive(
      const GameOverMessage(
        seq: 6,
        matchId: 'm1',
        ranking: [PlayerColor.red, PlayerColor.yellow],
        winners: [PlayerColor.red],
        serverSeed: 'aa',
        clientSeed: 'x:1',
        walletDelta: {},
      ),
    );
    expect(find.text('You won!'), findsOneWidget);
    await tester.tap(find.byKey(const Key('results-home')));
    await settle(tester);
    expect(find.text('Hello, Amina'), findsOneWidget);
    await app.stop();
  });

  testWidgets('play with friends creates a room and opens it', (tester) async {
    final app = App(tester);
    await app.start();
    await tester.tap(find.byKey(const Key('play-friends')));
    await settle(tester);
    await tester.tap(find.text('2 v 2 teams'));
    await settle(tester);
    expect(app.api.calls, ['create tok-1 teams 4']);
    expect(find.text('Room ABC234'), findsOneWidget);
    await app.stop();
  });

  testWidgets('leaving a running game asks first', (tester) async {
    final app = App(tester);
    await app.start();
    app.links.add(Uri.parse('arena://r/ABC234'));
    await settle(tester);
    await app.receive(gameState());
    await tester.tap(find.byTooltip('Leave'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('confirm-leave')));
    await settle(tester);
    expect(app.connector.last.sent.last, isA<LeaveRoomMessage>());
    expect(find.text('Hello, Amina'), findsOneWidget);
    await app.stop();
  });

  testWidgets('a missing room says so', (tester) async {
    final app = App(tester);
    await app.start();
    app.links.add(Uri.parse('arena://r/ABC234'));
    await settle(tester);
    await app.receive(
      const ErrorMessage(code: 'room_not_found', message: 'x', ref: 1),
    );
    expect(find.text('Room ABC234 was not found'), findsOneWidget);
    await app.stop();
  });

  testWidgets('pass and play is on the home screen', (tester) async {
    final app = App(tester);
    await app.start();
    await tester.tap(find.byKey(const Key('pass-and-play')));
    await settle(tester);
    expect(find.byType(LocalSetupScreen), findsOneWidget);
    await app.stop();
  });
}

/// Like pumpAndSettle, but finishes while a spinner keeps animating.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

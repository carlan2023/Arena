# Contract: app to server protocol

Status: frozen on 25 Sep 2026 for M2. Owner: Server. Changes go through the supervisor and are logged in docs/decisions.md.

The message classes, the fair dice function and a headless client live in one shared pure Dart package, packages/arena_protocol (pub name `arena_protocol`), owned by Server. The app and the server both import it, so the wire format exists once. It depends on `ludo_engine` and `crypto` only (plus `web_socket_channel` for the headless client, which must not import dart:io at the top level of the library the app imports; put the headless client in its own library file `package:arena_protocol/client.dart`).

## HTTP

Base URL from the app setting `ARENA_SERVER_URL`, for example http://10.0.2.2:8080 on the Android emulator. All bodies are JSON. Every route except login, health and payment callbacks needs `Authorization: Bearer <sessionToken>`.

| Method and path | Body | Response |
|---|---|---|
| GET /health | | `{"ok": true, "version": "..."}` |
| POST /v1/auth/login | `{"idToken": "..."}` | `{"sessionToken": "...", "user": User}` |
| GET /v1/me | | `User` |
| PATCH /v1/me | `{"displayName": "..."}` | `User` |
| POST /v1/rooms | `{"mode": "oneVsOne", "seats": 2, "stake": 0, "rules": RulesConfig?}` | `Room` |
| GET /v1/rooms/{code} | | `Room` |
| GET /v1/wallet | | `{"balance": int, "currency": "UGX"}` |
| GET /v1/wallet/history?limit=50 | | `{"entries": [WalletEntry]}` |
| POST /v1/wallet/deposits | `{"amount": int, "msisdn": "2567...", "provider": "mtn"}` | `Payment` with status pending |
| GET /v1/wallet/deposits/{id} | | `Payment` |
| POST /v1/payments/callback/{provider} | provider specific | 200 always once parsed, even for duplicates |
| POST /v1/dev/payments/{id}/confirm | | Only when PAYMENTS_PROVIDER=fake. Simulates the provider callback |
| GET /v1/matches/{id}/verify | | `{"serverSeed", "serverSeedHash", "clientSeed", "rolls": [[a,b]...]}` after the match ends |

Types:

```
User     {"id": str, "phone": str, "displayName": str}
Room     {"code": str, "link": str, "mode": str, "seats": int, "stake": int, "status": "waiting|playing|finished",
          "players": [{"seat": int, "userId": str, "displayName": str, "color": str, "isBot": bool, "connected": bool}]}
Payment  {"id": str, "provider": "fake|mtn|airtel", "amount": int, "status": "pending|succeeded|failed", "createdAt": iso8601}
WalletEntry {"txId": str, "kind": str, "amount": int, "balanceAfter": int, "at": iso8601}
Error    {"error": {"code": str, "message": str}}
```

Room codes are 6 characters from `ABCDEFGHJKMNPQRSTUVWXYZ23456789`. The link is `${PUBLIC_BASE_URL}/r/${code}`. The app routes `/r/:code` to the room lobby. Rooms with a stake above 0 are refused with `paid_tables_disabled` until M3.9.

HTTP errors use status 400, 401, 403, 404, 409 or 429 with the Error body.

## Web socket

`GET /v1/ws?token=<sessionToken>` upgrades to a web socket. Text frames, one JSON object per frame.

Every message has `"type"`. Client messages carry `"cseq"`, a counter the client increments per message; the server echoes it as `"ref"` in any reply or error it causes. Server messages about a room carry `"seq"`, a per room counter that increases by one for every room event broadcast to all seats. Direct replies to one client (errors, pong) carry no seq.

### App to server

| type | Fields | Notes |
|---|---|---|
| join_room | `roomCode: str, clientSeed: str?, lastSeq: int?` | Takes a seat, or returns to your seat. Reply is room_state to you. clientSeed is at most 64 characters, used only on first join |
| start_game | | Room owner only, with at least 2 seated players. Rooms also start by themselves when every seat is full |
| roll | | Your turn, phase awaitingRoll |
| move | `moves: [Move]` | The full list of steps for the current roll, in order, as engine Move JSON. Checked one step at a time with the engine. All or nothing |
| leave_room | | Leaves the lobby, or forfeits a running game |
| emote | `id: str` | Relayed to the room as emote. Ignored while not seated |
| ping | | Reply pong |

### Server to app

| type | Fields | Sent |
|---|---|---|
| room_state | `seq, room: Room, state: GameState?, deadline: int?, serverSeedHash: str?, you: {seat: int, color: str?}` | Reply to join_room, and broadcast when players join, leave, connect or disconnect in the lobby, and on game start. Full snapshot. `state` is engine GameState JSON, null before the start. `deadline` is epoch milliseconds when the current decision times out |
| dice | `seq, color: str, values: [int, int], rollNumber: int, legalMoves: [Move], state: GameState, deadline: int, auto: bool` | After every roll. `auto` true when the server rolled on timeout. If legalMoves is empty the state already shows the turn passed |
| state_patch | `seq, color: str, moves: [Move], captured: [PieceRef as {"c", "i"}], state: GameState, deadline: int?, auto: bool` | After a move list is applied. `auto` true for timeout and bot moves |
| player_status | `seq, seat: int, connected: bool, graceDeadline: int?, isBot: bool` | Disconnects, reconnects, bot takeover |
| emote | `seq, seat: int, id: str` | |
| game_over | `seq, ranking: [str], winners: [str], serverSeed: str, clientSeed: str, walletDelta: {str: int}` | Once. walletDelta maps userId to the change in their wallet, empty for free games |
| error | `ref: int?, code: str, message: str` | To one client |
| pong | `ref: int?` | |

Error codes: `bad_request`, `unauthorized`, `room_not_found`, `room_full`, `already_started`, `not_in_room`, `not_your_turn`, `wrong_phase`, `illegal_move`, `not_owner`, `rate_limited`, `paid_tables_disabled`, `insufficient_funds`, `internal`.

An illegal move list leaves the state unchanged and the timer running.

### Turns and timers

1. Each decision (roll, or the move list after a roll) has 20 seconds (`TURN_SECONDS`, default 20).
2. On timeout the server rolls, or plays the move list chosen by the normal bot from packages/ludo_bots, and broadcasts with `auto: true`.
3. After 3 timeouts in a row by one seat: in free games a bot takes the seat (player_status isBot true); in paid games the seat forfeits. A player who acts again takes the seat back from the bot in free games.
4. Tests can shorten timers through server settings.

### Reconnect

1. A seat whose socket closes is marked disconnected (player_status with graceDeadline = now + 60 s, `RECONNECT_GRACE_SECONDS`). Its timer keeps running and timeouts play for it.
2. Sending join_room with the same roomCode on a new socket within the grace period restores the seat. The reply is a full room_state snapshot. lastSeq is informational: the snapshot is always complete.
3. After the grace period the seat is handed to a bot in free games, or forfeits in paid games.
4. The same user joining from a second socket replaces the first socket.

### Seats and colours

Seats fill in join order. Colours by seat count: 2 seats: red, yellow. 3 seats: red, green, yellow. 4 seats: red, green, yellow, blue. Teams need 4 seats, partners red with yellow and green with blue.

## Fair dice (README section 11)

In `package:arena_protocol/fair_dice.dart`, used by the server to roll and by the app to verify.

1. At match creation the server makes a 32 byte random `serverSeed` (Random.secure) and publishes `serverSeedHash = hex(sha256(serverSeed bytes))` in room_state before the first roll.
2. `clientSeed` is the client seeds of the seated players in seat order, joined with `:`. A player who sent none contributes their seat number. It is fixed when the game starts.
3. Roll number n (the engine's `rollNumber` before the roll, from 0) gives `h = HMAC_SHA256(key: serverSeed bytes, message: utf8("$clientSeed:$n"))`. Read bytes of h in order and skip any byte of 252 or more; the first usable byte b gives die1 = b % 6 + 1, the next gives die2. If the 32 bytes run out, continue with HMAC over `"$clientSeed:$n:1"`, then `:2`, and so on.
4. At game over the server reveals serverSeed. Anyone can check `sha256(serverSeed) == serverSeedHash` and recompute every roll.

```dart
String hashServerSeed(List<int> serverSeed);          // lowercase hex
(int, int) rollDice(List<int> serverSeed, String clientSeed, int rollNumber);
bool verifyRolls({required String serverSeedHex, required String serverSeedHash,
                  required String clientSeed, required List<(int, int)> rolls}); // rolls[i] is roll number i
```

## Message classes

`arena_protocol` exposes one Dart class per message with `toJson` and `fromJson`, and `ClientMessage.decode(String)` and `ServerMessage.decode(String)` that return the right subclass, throwing `ProtocolException` on bad input. Unknown message types from the server are ignored by the client so the server can add messages.

## Headless client

`package:arena_protocol/client.dart` exposes `ArenaClient` for tests and bots: login over HTTP, create or join a room, a stream of ServerMessage, send methods for each client message, and `disconnect()` for tests that force a drop. The server integration test and the app's online game use this client or the same message classes.

## Amendments at freeze (25 Sep 2026)

These settle the review round and override anything above that disagrees.

1. Room gains `ownerUserId: str` and `matchId: str?` (null before the start). game_over gains `matchId`. `ranking` and `winners` are colour strings; `walletDelta` is keyed by userId.
2. room_state, dice and state_patch gain `serverNow: int` (epoch ms) so the app computes time left without trusting the phone clock. pong carries it too.
3. The room_state reply to join_room carries the room's current seq and does not increase it. A client that sees a gap in seq sends join_room again for a fresh snapshot.
4. Seats are numbered from 0. Colours are given at the start from the number of players actually seated (3 players in a 4 seat free for all get red, green, yellow), so `color` is null in the lobby. oneVsOne needs seats 2 and starts with 2. teams needs seats 4 and starts with 4. freeForAll allows seats 2 to 4 and starts with 2 or more. Anything else is bad_request.
5. A seat freed in the lobby goes to the next joiner (lowest free seat). If the owner leaves, the lowest seated player becomes owner. An empty waiting room expires after ROOM_IDLE_MINUTES, default 30. join_room on a finished room, or on a running room where you hold no seat, returns already_started.
6. A socket is bound to one room by join_room. A user holds a seat in at most one waiting or playing room; joining another returns bad_request.
7. Timeouts: each timed out decision (a roll or a move list) counts 1; any action by the player resets the count to 0. Bots act after BOT_DELAY_MS, default 800. In free games a seat taken by a bot, after timeouts or after the reconnect grace, returns to the player on join_room or on their next roll or move.
8. A running game with no connected human left ends as abandoned: logged with status abandoned, the room finishes, no game_over is sent.
9. clientSeed is 1 to 64 characters from A-Z a-z 0-9 _ -. serverSeed and its hash are made at room creation and shown in every room_state, before any client seed is seen. One match per room in M2.
10. arena_protocol may use `http` too, only in client.dart.
11. Live rooms: one server instance in M2. Rooms in memory are the authority; every room event is written through a `LiveRoomStore` interface (Redis, and an in memory fake) holding snapshot, seq, deadline and seats, with a TTL. On restart the server reloads live rooms from Redis and re-arms their timers. Several instances are M3 work.
12. Server owns every HTTP route in server/lib, calling only AuthService, Ledger and PaymentsService from the Wallet packages. GET /v1/wallet/deposits/{id} returns 404 for another user's payment and calls `refresh` while pending. WalletEntry maps from LedgerEntry, with kind from the transaction kind. The dev confirm route calls `FakePaymentProvider.complete(id)` then `PaymentsService.refresh(id)`.
13. GET /r/{code} serves a small HTML page that opens the app through the arena://r/{code} link and otherwise points to the download. The app accepts both /r/{code} links and arena://r/{code}.
14. Fake login id tokens are `fake:+256XXXXXXXXX` (E.164). The app sends the phone in that form.
15. Defaults: server migration ids `server_NNN_name`, run under a Postgres advisory lock. Room creation limit 10 per user per hour, 20 web socket messages per second per socket, above which rate_limited. Emote ids up to 32 characters. The token query parameter is never logged. /health version from APP_VERSION, default dev. Paid game rules (forfeit on timeout and after grace) sit behind stake > 0 and are unit tested only, since paid rooms are refused in M2. The server refuses to start with AUTH_PROVIDER=fake and a real PAYMENTS_PROVIDER.

## Amendment: guest play (26 Sep 2026, D33)

1. `POST /v1/auth/guest` with no body returns `{"sessionToken", "user"}` for a new guest account. No phone and no code. Limited per client address by GUESTS_PER_HOUR, default 30, then 429 rate_limited.
2. `User` gains `isGuest: bool`, true when the account has no verified phone.
3. Guests may create, join and play free rooms like anyone else.
4. The wallet routes (`GET /v1/wallet`, `GET /v1/wallet/history`, `POST /v1/wallet/deposits`) and creating a room with a stake refuse guests with 403 `phone_required`. Joining a paid room will do the same when paid tables arrive in M3.9.
5. The app never asks for a login before free play. It starts a guest session the first time the player goes online, and offers the phone login only for paid play and the wallet. A guest token the server no longer accepts is replaced by a new guest.

## Amendment: combined moves (26 Sep 2026, D34)

The `move` message may contain the new engine move kind `combined` (engine_api.md, D34), sent as one element: `{"k":"combined","c":"red","p":[2],"d":4,"d2":4}`. The server checks it with the engine like any other step.

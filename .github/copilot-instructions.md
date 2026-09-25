# Notes for AI coding agents

Arena is a Flutter app for Ugandan Ludo with a Dart game server. Read these first; they are the source of truth and this file only points at them:

- README.md: product, game rules (section 2), milestone tracker (section 4), technical design (section 6), how we work and CI (section 13).
- docs/contracts/: frozen interfaces. ownership.md says who owns which folder; engine_api.md, protocol.md and wallet_api.md define the shared APIs. Change them only through the supervisor.
- docs/decisions.md: the decision log, including current rule defaults.

## Layout

| Folder | What |
|---|---|
| apps/mobile | Flutter app (package `arena`) |
| packages/ludo_engine | Pure Dart rules engine, shared by app and server |
| packages/ludo_bots | Bots built on the engine |
| packages/arena_protocol | Wire messages, fair dice, headless client |
| server | Dart game server (shelf, web sockets, Postgres, Redis) |
| server/auth, server/wallet | Login and wallet packages used by the server |

Packages depend on each other by path only; nothing is published.

## Rules of thumb

- The server has the final say; rules live only in packages/ludo_engine. Never copy rule logic into the app or server.
- Tests come with every change. Each package runs `dart format`, `dart analyze --fatal-infos` (or `flutter analyze --fatal-infos`) and its tests in CI; the engine needs 95 percent line coverage.
- No keys, passwords or tokens in the repo. Every outside service has an interface and a fake.
- Commit messages start with the task ID, for example `M1.2 add legal move generation for two dice`.

## Running things

```
cd apps/mobile && flutter pub get && flutter test
cd packages/ludo_engine && dart pub get && dart test
cd server && dart pub get && dart test   # uses DATABASE_URL and REDIS_URL when set
```

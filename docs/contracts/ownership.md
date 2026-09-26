# Contract: who owns which folders

Status: frozen 25 Sep 2026. Owner: Supervisor. Changes go through the supervisor and are logged in docs/decisions.md.

Only the owner edits files in a folder. Anything outside your folders goes to the supervisor as a change request: what, why, and who else it affects. The supervisor makes all commits.

| Agent | Tasks | Folders |
|---|---|---|
| Supervisor | Contracts, review, integration tests, commits, README tracker, decision log | README.md, docs, server/test/integration, root files not listed below |
| Foundations | M0.4 bugs B1 to B6 and B8, M0.6 repo restructure, M0.7 CI | .github, .gitattributes, .gitignore, analysis_options.yaml at the root, the move of the Flutter project into apps/mobile |
| Engine | M1.1 to M1.6, then M1.10 bots | packages/ludo_engine, packages/ludo_bots |
| Client | M1.7 to M1.9, M1.11, M2.12 and the app side of M2.3 | apps/mobile (after Foundations hands it over) |
| Server | M2.1, M2.2, M2.4 to M2.8 | server (except server/auth, server/wallet and server/test/integration), packages/arena_protocol, docker-compose.yml, .dockerignore, server/Dockerfile, server/.env.example |
| Wallet | M2.3 server side, M2.9 to M2.11 | server/auth, server/wallet |

## Packages

| Folder | Pub name | Depends on |
|---|---|---|
| packages/ludo_engine | ludo_engine | nothing outside the Dart SDK (test deps only) |
| packages/ludo_bots | ludo_bots | ludo_engine |
| packages/arena_protocol | arena_protocol | ludo_engine, crypto, http, web_socket_channel |
| server/auth | arena_auth | http, crypto, postgres, pointycastle or asn1lib for RS256 |
| server/wallet | arena_wallet | arena_auth (Migration type only), http, postgres, crypto |
| server | arena_server | all of the above by path, shelf, shelf_router, shelf_web_socket, postgres, redis |
| apps/mobile | arena | ludo_engine, ludo_bots, arena_protocol by path, flutter_riverpod, go_router, shared_preferences, share_plus, app_links, http, web_socket_channel |

Path dependencies only, no publishing. Every package has its own analysis_options.yaml that includes package:lints/recommended.yaml (package:flutter_lints for the app) and its own tests.

## Shared rules

1. Tests come with the code. A task is not done without tests.
2. No secrets in the repo. Read them from the environment in server/lib/config.dart only.
3. Every outside service has an interface and a fake.
4. `dart format` clean, `dart analyze --fatal-infos` (or `flutter analyze`) with no issues.
5. Workers may set their own task rows in the README to In progress. Nothing else in the README.
6. Do not commit. Hand work to the supervisor.

## Lockfiles and analysis

pubspec.lock is committed for apps/mobile and server, and ignored for the library packages. The root analysis_options.yaml moves to apps/mobile; each package has its own.

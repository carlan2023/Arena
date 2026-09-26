# Decision log

Short records of decisions made while building. Rule defaults here are placeholders until Allan decides M0.3; each is a RulesConfig setting so a change needs no rewrite.

| No. | Date | Decision | Why |
|---|---|---|---|
| D1 | 25 Sep 2026 | R1 default: three double 6s in a row do not cancel the turn. Setting tripleDoubleSixCancelsTurn | Session brief default, pending Allan |
| D2 | 25 Sep 2026 | R2 default: both dice must be used when possible. If only one fits, the player chooses which. Setting mustUseBothDice | Matches the proposed default in the old README, pending Allan |
| D3 | 25 Sep 2026 | R3 default: a block moves by one die value on a double, using both dice. Setting blockMoveUsesSum | Pending Allan |
| D4 | 25 Sep 2026 | R4 default: a piece that lands on its own block cannot continue past it in the same roll. Setting canContinuePastOwnBlock | Pending Allan |
| D5 | 25 Sep 2026 | R5 default: sixes are counted across all rolls in the turn, the current roll included. A double 6 must still come first. Setting countSixesAcrossTurn | Pending Allan |
| D6 | 25 Sep 2026 | Blocks and captures exist only on the 52 shared track squares. Home columns and the finish never block | The rules only describe blocks as walls to opponents, who never enter your home column. Added to the questions for Allan |
| D7 | 25 Sep 2026 | R6 default: free for all continues for second and third place. Setting freeForAllPlaysOn | Pending Allan |
| D8 | 25 Sep 2026 | R7 default: a 2v2 team wins when both partners finish. Setting teamWinsWhenBothFinish | Pending Allan |
| D9 | 25 Sep 2026 | R8 default: no joint blocks, and a finished player rolls for the partner. Settings partnersFormJointBlocks and finishedPlayerRollsForPartner | Pending Allan |
| D10 | 25 Sep 2026 | Progress model: -1 home, 0 start square, 51 last track square, 52 to 56 home column, 57 finished | Gives the 57 steps in README section 2 |
| D11 | 25 Sep 2026 | The client sends the whole list of steps for a roll in one move message. The server checks each step with the engine, all or nothing | Undo is free until the last die, as README section 7 asks, and one message per roll keeps data low |
| D12 | 25 Sep 2026 | Bots live in a pure Dart package, packages/ludo_bots, built by Engine instead of Client | The server needs the same bot for timeout moves and bot seats. Engine is free after M1.6 and Client has the most work |
| D13 | 25 Sep 2026 | Protocol messages, fair dice and a headless client live in packages/arena_protocol, owned by Server | One wire format for app, server and tests |
| D14 | 25 Sep 2026 | Login and wallet code are separate packages, server/auth and server/wallet, used by the server by path | Clean ownership, and they can be tested without the game server |
| D15 | 25 Sep 2026 | The server issues its own session token after checking the Firebase ID token once, signed with SESSION_SECRET | Firebase tokens expire hourly; the wallet routes and web socket need one stable bearer token |
| D16 | 25 Sep 2026 | With AUTH_PROVIDER=fake the app's login accepts code 123456 and sends fake:<phone>. Default is fake until the Firebase project exists | Two phones can log in and play before M0.5 and the Firebase project are decided |
| D17 | 25 Sep 2026 | Paid rooms are refused with paid_tables_disabled until M3.9. M2 only proves deposits reach the wallet | Stakes and settlement are M3 work |
| D18 | 25 Sep 2026 | This session works on branch claude/arena-m0-m1-m2-build-xy3qa3 and is merged to main from there | The session is only allowed to push to that branch |
| D19 | 25 Sep 2026 | Contracts frozen after review by all five workers. Engine got 14 clarifications, protocol 15, wallet 14, and bots_api.md was added | Review round, see the amendment sections in each contract |
| D20 | 25 Sep 2026 | Engine exposes blocks, hasBlockRights and legalSequences | The app needs them for the cracked block bar, the both dice ghost and auto play, and bots need the same enumeration, so no rule is copied |
| D21 | 25 Sep 2026 | Teams: if one partner forfeits, the other team wins | Under R7 default the team can no longer win. Added to the questions for Allan |
| D22 | 25 Sep 2026 | Payment callbacks are hints; the wallet is credited on the provider's own status answer | MTN callbacks are unsigned and Airtel's signature is optional |
| D23 | 25 Sep 2026 | MTN sandbox deposits are requested in EUR, recorded in UGX | The MTN sandbox only accepts EUR |
| D24 | 25 Sep 2026 | App defaults: online board rotated so your home is bottom left; the both dice ghost avoids an optional capture on the middle square; a block moves by tapping a block piece and its block spot; ARENA_SERVER_URL from dart-define, default http://10.0.2.2:8080 | Client review round |
| D25 | 25 Sep 2026 | CI also runs on pushes to claude/** branches, pins Flutter 3.47.5 and Dart 3.13.4, and uses one matrix job over every Dart package | Foundations review round |
| D26 | 25 Sep 2026 | Decisions are logged in this file rather than docs/adr | One short file is easier to keep current. README section 13 updated to match |
| D27 | 25 Sep 2026 | Engine Move constructors are not const (they copy and sort piece lists). PieceRef JSON is {"c": colour, "i": index}, and the protocol's captured list uses the same form. Engine adds copyWith helpers and progressOf | Engine checkpoint 2, additive changes |
| D28 | 25 Sep 2026 | Payment callback routes accept PUT as well as POST | MTN sends callbacks as PUT in some environments |
| D29 | 26 Sep 2026 | forfeit throws StateError once the game is over, and legalMoves returns an unmodifiable list cached per state | Engine final report, additive |
| D30 | 26 Sep 2026 | With PAYMENTS_PROVIDER=fake every deposit goes to the fake provider. The dev confirm route only confirms the caller's own payment and also accepts a failed status | Local and test runs need no provider accounts |
| D31 | 26 Sep 2026 | A forfeit is broadcast as a full room_state. leave_room in the lobby sends no reply to the leaver. A lobby player who drops loses the seat after the 60 second grace | No dedicated protocol message is needed for M2 |
| D32 | 26 Sep 2026 | With fake login and fake payments a missing SESSION_SECRET is made at random on start, so docker compose up works with no setup. Otherwise the server refuses to start without one | One command local stack |

## Open for Allan

| No. | Question or need | Current default |
|---|---|---|
| Q1 | Rules R1 to R8 (M0.3) | D1 to D9 above |
| Q2 | Blocks only on the shared track, never in home columns | Yes (D6) |
| Q3 | In teams, what happens when one partner forfeits | The other team wins (D21) |
| Q4 | Brand name, domain and Android package id (M0.5, B7) | com.example.ludo_stake, arena:// links |
| Q5 | Google Play account, personal or organisation (M0.8) | None |
| Q6 | Figma wireframes (M0.9) | None |
| Q7 | MTN MoMo and Airtel developer accounts (M0.10, M2.10) | Fake provider |
| Q8 | Firebase project for phone codes (M2.3) | Fake login, code 123456 |
| Q9 | Hosting account, staging domain and GitHub DEPLOY secrets (M2.8) | Local docker compose |
| Q10 | Old email login and grid board files in apps/mobile/lib/screens, widgets, services and models are unused; approve deleting them | Kept, unused |
| Q11 | Luganda text for quick chat and the app | English only |

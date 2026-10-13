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
| D33 | 26 Sep 2026 | Guest mode: free play needs no login. The app starts a guest account on the first online action; the phone login is asked for only for paid tables and the wallet, which the server refuses to guests with phone_required | A login wall before a free game drives players away. Money needs a verified phone |
| D34 | 26 Sep 2026 | A piece captures only where it stops. A combined move (both dice on one piece) is one move that passes single pieces without capturing. A capture stops that piece for the roll; using both dice comes before capturing; forced landings still capture; the stop lasts one roll, so the extra roll after a double 6 frees it; a release that captures also stops the piece | Decided by Allan after a report that a 4 and 4 move captured the piece it passed |
| D35 | 10 Oct 2026 | Avatars: 16 preset avatars, numbers 0 to 15, plus the display name. No photo upload | Placeholder for Allan (Q12). No moderation cost at MVP. Full text in docs/contracts/m3.md section 2 |
| D36 | 10 Oct 2026 | Coins: 500 on an account's first login, guests included. Daily reward 100, plus 20 per streak day up to day 7 (220); a missed day resets the streak; once per Kampala calendar day | Placeholder for Allan (Q12). Server settings |
| D37 | 10 Oct 2026 | Coin tables: entry 0, 50, 200 or 1000 coins. Winner takes the pot, no house share. In four player games 2nd place gets its entry back and the winner takes the rest | Placeholder for Allan (Q12). Server settings |
| D38 | 10 Oct 2026 | Paid tables: 1v1 only, stakes 1000 to 50000 UGX, house share 12 percent, taxes per README section 10. No bots, no guests, timeouts forfeit. Off unless PAID_TABLES_ENABLED=true | Placeholder for Allan (Q12). Matches README section 10 |
| D39 | 10 Oct 2026 | Quick match: a queue per mode and table. Free and coin queues fill empty seats with bots after 20 seconds (BOT_FILL_SECONDS). Paid queues never get bots and time out after 60 seconds with no charge | Placeholder for Allan (Q12). README section 12 target of a game within 20 seconds |
| D40 | 10 Oct 2026 | Age and limits: paid tables and the wallet need a phone login and a date of birth at least MIN_AGE (25) years ago. Player deposit limits per day, week and month under a house cap of 1,000,000 UGX a day; lowering is immediate, raising waits 24 hours. Self exclusion for 1 day, 7 days, 30 days, 6 months or permanently | Placeholder for Allan (Q12). README section 10, player protection |
| D41 | 10 Oct 2026 | Withdrawals: 1000 to 2,000,000 UGX, a person approves at or above 200,000 UGX (MANUAL_REVIEW_UGX), money held in a pending account until the provider answers | Placeholder for Allan (Q12). Not built in this round: M3.13 waits on live providers |
| D42 | 10 Oct 2026 | Tutorial: five lessons (release with a 6, combine dice, make a block, break a block, exact finish) with fixed dice and a scripted bot; 50 coins for finishing all five, once per account | Placeholder for Allan (Q12). README section 7, first time players |
| D43 | 10 Oct 2026 | Two Android flavours: play (free and coin play only) and full (everything, from our website). The server can still switch paid play off | Placeholder for Allan (Q12). README section 10, builds |
| D44 | 10 Oct 2026 | Luganda: the app has English and Luganda files, Luganda strings stay empty and fall back to English until a native speaker writes them. Nothing is machine translated | Placeholder for Allan (Q11, Q12) |
| D45 | 13 Oct 2026 | CORS: ALLOWED_ORIGINS lists the browser origins that may call the API and open the web socket, default https://arena-cddfa.web.app, https://arena-cddfa.firebaseapp.com and http://localhost on any port. Preflights from other origins get 403; a web socket from another browser origin gets 403. Requests with no Origin header (the Android app, payment callbacks) are unchanged | The web app on Firebase Hosting needs it for online play (m3.md section 0). An allow list rather than * keeps other sites from using a player's session in the browser |
| D46 | 13 Oct 2026 | Android APKs are built per processor type (--split-per-abi). Releases and the website download offer arm64-v8a and armeabi-v7a; x86_64 is built but not published. CI fails above 30 MB for either. The Play Store keeps getting the app bundle | One APK for every processor was 54.8 MB, above the 30 MB target in README section 7. x86_64 is only for emulators and Chromebooks |
| D47 | 13 Oct 2026 | CI runs Postgres and Redis on the runner itself, not as service containers: the PostgreSQL that comes with GitHub's Ubuntu image and redis-server from the Ubuntu archive (.github/scripts/start_databases.sh). Only the server, server/auth and server/wallet jobs start them | Docker Hub's anonymous pull limit failed every Dart job on Dependabot pull request 13. The AWS mirror of the Docker library was tried next and also refused anonymous pulls (data limit exceeded). The engine, bots and protocol packages never use a database |
| D48 | 13 Oct 2026 | M3 contract reviewed and frozen. Three small fixes made in the review, six bigger items assigned to their tasks (docs/contracts/m3.md section 0) | Section 0 review pass before M3 work |

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
| Q8 | Firebase project for phone codes (M2.3) | Fake login, code 123456. Guests need no login (D33) |
| Q9 | Hosting account, staging domain and GitHub DEPLOY secrets (M2.8) | Local docker compose |
| Q10 | Old email login and grid board files in apps/mobile/lib/screens, widgets, services and models are unused; approve deleting them | Kept, unused |
| Q11 | Luganda text for quick chat and the app | English only |
| Q12 | M3 product defaults: avatars, coin amounts, coin and paid tables, quick match timing, age and limits, withdrawals, tutorial, flavours (D35 to D44) | The placeholders in D35 to D44 |
| Q13 | How to keep friends from meeting each other in paid queues (README section 10). The server has no friends list | Not enforced; paid tables are off (PAID_TABLES_ENABLED=false) |

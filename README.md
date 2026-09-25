# Arena

Arena is a mobile app for playing Ugandan Ludo online with friends, strangers and bots. We are building for Android first, in Flutter.

Paid play is part of the first release. Players deposit with MTN MoMo or Airtel Money and stake on games. Licensing is handled by Allan and is outside the scope of this document.

This file is the main reference for the team. The milestone tracker in section 4 is updated with every commit.

## 1. The product

### Who it is for

Our main players are young adults aged 18 to 35 in Kampala and other towns. Most use Android phones and watch their data. We also expect players who already use betting apps and want a game where skill matters.

### How people play

| Way to play | Description |
|---|---|
| Friends | Create a private room and share the link or code on WhatsApp |
| Quick match | Join a queue and get matched with other players |
| Practice | Play against the computer |

Game modes are 1v1, four player free for all, and 2v2 teams.

### How we make money

Players deposit into an Arena wallet with MTN MoMo or Airtel Money and stake between UGX 1,000 and UGX 50,000 on a game. We keep 10 to 15 percent of each pot. Stakes may be held as coins bought with deposits. The wallet works the same way in either case.

Free coin tables, rewarded ads and cosmetic items run alongside paid play. Bots never sit at a paid table.

### Why people will choose Arena

1. It plays by our rules. Ludo King and Ludo Club use the international single die rules. Nobody serves the Ugandan game properly.
2. It suits local phones and networks: small download, low data use, and games that survive a dropped connection.
3. It feels local, with Luganda in the app and invites that go straight to WhatsApp.
4. The dice can be checked. Every roll can be verified after the game, so players can trust the results when money is at stake.

## 2. Game rules

The rules engine follows this section exactly. If a rule changes, update this section first, then the code and tests.

### Board and pieces

The board has 52 track squares, a start square for each colour, and a home column of 5 squares leading to the centre. A piece needs 57 steps from its start square to finish. There are four colours with four pieces each, and turns go clockwise.

### Dice

Each turn a player rolls two dice. The values can be used on two different pieces or added together on one piece. With a 3 and a 5, you can move one piece 3 and another 5, or move one piece 8. A combined move is played as two steps, and each step must be legal on its own.

A double 6 earns another roll after you have played your moves.

### Leaving home

A piece leaves home when either die shows a 6. That 6 is used up placing the piece on its start square. The other die can move any piece, including the one just released.

### Moving

If a legal move exists, you must play it. Capturing is optional, so you can pick a different move instead. If no move is possible, the turn passes.

### Capturing

Landing on a single opponent piece sends it home. There is no bonus for a capture and there are no safe squares on the board, start squares included. The only protection is a block.

### Blocks

A block is two or more pieces of the same colour on one square.

1. Opponent pieces cannot pass a block.
2. Your own pieces cannot jump over your block either. They can join it by landing on it exactly.
3. On a double, the whole block can move together.

### Capturing a block

To capture a block of two, the attacker must first roll a double 6. On the extra roll, the attacker has to land exactly on the block. If the roll carries the piece beyond the block, the attacker may move past it, because the double 6 opens the block for that turn.

A block of three needs three sixes and a block of four needs four sixes, plus the exact distance. When a block is captured, every piece in it goes home.

### Finishing

A piece needs an exact roll to finish. A piece 4 steps from the centre can use a 4, or a 1 and a 3, but not a 5. A player wins when all four pieces are home.

### Teams

In 2v2, partners sit opposite each other. A player may capture a partner's piece by choice, and must do so if it is the only legal move.

### Online timing

Each decision has 20 seconds. When time runs out, the server plays the best legal move. After three timeouts in a row, a bot takes over in free games and the player forfeits in paid games. A player who disconnects has 60 seconds to rejoin. A full game should take 15 to 30 minutes.

### Test cases for the engine

| Situation | Expected result |
|---|---|
| Red has every piece at home and rolls 6 and 3 | Red releases a piece with the 6 and moves it 3 |
| A blue piece is 5 squares behind a red block of two and rolls 4 and 6 | The 4 can move that piece, the 6 cannot. The 6 must be used elsewhere |
| Same position, Blue rolls 6 and 6, then 5 and 2 | Blue lands on the block with the 5 and both red pieces go home |
| Same position, Blue rolls 6 and 6, then 6 and 3 | Blue may move 6 past the block. Nothing is captured |
| A yellow piece is 4 steps from the centre and rolls 5 and 2 | The 5 cannot move that piece. The 2 can |

### Rules still to decide

These need a decision from Allan before the engine is final. The engine will have a setting for each one so they can change without a rewrite.

| No. | Question |
|---|---|
| R1 | Do three double 6s in a row cancel the turn? |
| R2 | Must both dice be used when possible, and who chooses if only one can be used? |
| R3 | Does a block of two on 4 and 4 move 4 squares or 8? |
| R4 | After landing exactly on its own block, can a piece continue past on the second die? |
| R5 | For blocks of three and four, are the sixes counted across all rolls in one turn? |
| R6 | In free for all, does play continue for second and third place? |
| R7 | In 2v2, does the team win when both partners finish or when the first one does? |
| R8 | In 2v2, can partners form a block together, and does a finished player roll for the partner? |

## 3. Current state of the code

The Flutter project is named `arena` and lives at github.com/carlan2023/Arena, in the apps/mobile folder.

| File | What it does now |
|---|---|
| apps/mobile/lib/main.dart | Routes for login, home, register and board, plus the theme |
| apps/mobile/lib/screens/login_screen.dart | Validates the form, calls the auth service and shows a loading state |
| apps/mobile/lib/screens/register_screen.dart | Calls the stub auth service, then opens home |
| apps/mobile/lib/screens/home_screen.dart | Shows a welcome message and nothing else. The board cannot be reached from the app |
| apps/mobile/lib/screens/board_screen.dart | Shows the board and dice, with separate layouts for narrow and wide screens |
| apps/mobile/lib/widgets/ludo_board.dart | Draws a 15 by 15 grid of colours. No track, no pieces |
| apps/mobile/lib/widgets/dice_widget.dart | One die that rolls on tap |
| apps/mobile/lib/services/auth_service.dart | Returns a made up user after one second |
| apps/mobile/test | Smoke tests for login, register, the board and the dice |

### Known bugs

| No. | Bug | Status |
|---|---|---|
| B1 | The dice image for 6 is spelled assets/dice6).png, so the app crashes on every 6 | Fixed 25 Sep 2026 |
| B2 | The white inner squares of each home never show, because the corner colour rules run first | Fixed 25 Sep 2026 |
| B3 | The home arm colours do not line up with the corner colours | Fixed 25 Sep 2026 |
| B4 | Login never calls the auth service and the loading state never changes | Fixed 25 Sep 2026 |
| B5 | The link back to login on the register screen calls pop, but there is no screen to go back to | Fixed 25 Sep 2026 |
| B6 | The widget test is the Flutter counter template | Fixed 25 Sep 2026 |
| B7 | The Android package is still com.example.ludo_stake. It must change before the first Play Store upload, since it can never change afterwards | Waiting on M0.5 |
| B8 | .github/copilot-instructions.md describes an older version of the project | Not started |

We keep the project structure, the dice images and the folder layout. The email login will be replaced by phone number login. The grid board will be replaced by a drawn board driven by a track model, and the single die by two dice rolled on the server.

## 4. Milestones and progress

### Target

The public Android release is due by 31 December 2026, with mid January 2027 as the fallback. The team is two developers, usually working one at a time.

Paid play adds roughly three weeks of work to the plan. If dates slip, 2v2 moves out first, then withdrawals.

Google Play requires new personal developer accounts to run a closed test with at least 12 testers for 14 days before going live. So closed testing must start by 14 December, unless we register as an organisation.

### How to keep this tracker updated

With every commit to main:

1. Change the status of any task the commit moves forward. Use Not started, In progress, Done, or Blocked. A blocked task says why in its task text.
2. Enter the date in the Date done column when a task is finished.
3. Add one line to the progress log with the date, the task IDs and a plain description. Start the commit message with the same task ID so git log links back to the tracker.
4. Update the milestone summary if the overall status changed.

### Milestone summary

| Milestone | Dates | Status |
|---|---|---|
| M0 Foundations | 28 Sep to 9 Oct 2026 | In progress |
| M1 Rules engine and offline play | 12 Oct to 6 Nov 2026 | Not started |
| M2 Online rooms and wallet | 9 Nov to 27 Nov 2026 | Not started |
| M3 Matchmaking, paid tables and polish | 30 Nov to 11 Dec 2026 | Not started |
| M4 Closed beta | 14 Dec to 28 Dec 2026 | Not started |
| Release | 29 Dec to 31 Dec 2026 | Not started |

### M0 Foundations

Done when the rules are signed off, the known bugs are fixed, the repo is restructured and CI is running.

| ID | Task | Status | Date done |
|---|---|---|---|
| M0.1 | Write the project README and milestone tracker | Done | 25 Sep 2026 |
| M0.2 | Draft board layout and dice widget | Done | Before 25 Sep 2026 |
| M0.3 | Decide rules R1 to R8 | Not started | |
| M0.4 | Fix bugs B1 to B8 | In progress | |
| M0.5 | Choose the final brand name and Android package id | Not started | |
| M0.6 | Restructure the repo into apps/mobile, packages/ludo_engine and server | Done | 25 Sep 2026 |
| M0.7 | Set up GitHub Actions for CI, Android releases and server deploys | In progress | |
| M0.8 | Register the Google Play developer account | Not started | |
| M0.9 | Wireframe the core screens in Figma, including the wallet | Not started | |
| M0.10 | Choose the payment provider and open sandbox accounts | Not started | |

### M1 Rules engine and offline play

Done when a full game can be played offline against bots, with every rule in section 2 covered by tests.

| ID | Task | Status | Date done |
|---|---|---|---|
| M1.1 | Game state model: track, home columns, pieces, blocks | In progress | |
| M1.2 | Legal move generation for two dice | In progress | |
| M1.3 | Block rules, including block capture | In progress | |
| M1.4 | Exact finish and win detection | In progress | |
| M1.5 | Rule settings for R1 to R8 | In progress | |
| M1.6 | Unit tests covering every test case in section 2, with at least 95 percent coverage | In progress | |
| M1.7 | New board drawn with CustomPainter | Not started | |
| M1.8 | Pieces, move highlights and animations | Not started | |
| M1.9 | Two dice tray and move selection | Not started | |
| M1.10 | Easy and normal bots | In progress | |
| M1.11 | Pass and play on one phone for internal testing | Not started | |

### M2 Online rooms and wallet

Done when two to four people can finish a game online from a shared WhatsApp link, and a test deposit shows up in the wallet.

| ID | Task | Status | Date done |
|---|---|---|---|
| M2.1 | Dart game server with WebSocket rooms | Not started | |
| M2.2 | Server dice with verifiable rolls | Not started | |
| M2.3 | Phone number login with OTP | Not started | |
| M2.4 | Create room, join by code or link | Not started | |
| M2.5 | Turn timer and automatic moves | Not started | |
| M2.6 | Reconnect within 60 seconds | Not started | |
| M2.7 | Save match history and move log to Postgres | Not started | |
| M2.8 | Staging server running | Not started | |
| M2.9 | Double entry ledger for wallet balances and coins | Not started | |
| M2.10 | Deposits through MTN MoMo and Airtel Money in the sandbox | Not started | |
| M2.11 | Payment callbacks that are safe to receive twice | Not started | |
| M2.12 | App connects to the server: login, create and join rooms, online game, reconnect | Not started | |

### M3 Matchmaking, paid tables and polish

Done when strangers can find a game within 20 seconds, a paid 1v1 game settles correctly, and the app is ready for testers.

| ID | Task | Status | Date done |
|---|---|---|---|
| M3.1 | Quick match queue for 1v1 and four players | Not started | |
| M3.2 | Bots fill empty seats in free games after 20 seconds | Not started | |
| M3.3 | Profiles and avatars | Not started | |
| M3.4 | Coins and daily reward | Not started | |
| M3.5 | Luganda translation | Not started | |
| M3.6 | Sound and vibration | Not started | |
| M3.7 | Interactive tutorial | Not started | |
| M3.8 | 2v2 teams, which moves to January if time runs short | Not started | |
| M3.9 | Paid tables: stake taken on join, pot held until the game ends, then winner paid and our share taken | Not started | |
| M3.10 | Wallet screen with balance, deposit and history | Not started | |
| M3.11 | Deposit limits, minimum age check and self exclusion setting | Not started | |
| M3.12 | Live deposits with real providers, behind a server setting | Not started | |
| M3.13 | Withdrawals to mobile money, which moves to January if time runs short | Not started | |

### M4 Closed beta and release

| ID | Task | Status | Date done |
|---|---|---|---|
| M4.1 | Closed test with at least 12 testers for 14 days | Not started | |
| M4.2 | Crash free sessions at 99 percent or higher | Not started | |
| M4.3 | Store listing, privacy policy and data safety form | Not started | |
| M4.4 | Production release in Uganda | Not started | |
| M4.5 | Test paid play end to end with small real amounts | Not started | |
| M4.6 | Daily reconciliation of the ledger against provider statements | Not started | |

### After release

| Version | When | Focus |
|---|---|---|
| 1.1 | January 2027 | 2v2 if it slipped, friends list, rematch, quick chat, shareable results |
| 1.2 | February and March 2027 | Coin tournaments, leaderboards, seasons, cosmetics shop, iOS |
| Paid play expansion | From January 2027 | Withdrawals if they slipped, paid four player tables, paid tournaments, identity checks |

### Progress log

| Date | Tasks | Change |
|---|---|---|
| Before 25 Sep 2026 | | Flutter project created |
| Before 25 Sep 2026 | | Login, register and home screens added |
| Before 25 Sep 2026 | M0.2 | Board layout and dice widget |
| 25 Sep 2026 | M0.1 | Project README added |
| 25 Sep 2026 | M0.1 | README rewritten in plain language, milestone tracker added |
| 25 Sep 2026 | M0.1 | Paid play moved into the first release, wallet and paid table tasks added |
| 25 Sep 2026 | M0.7 | CI and CD workflows written, Android release signing added to Gradle |
| 25 Sep 2026 | M0.6 | Contracts for the engine, protocol, wallet, bots and folder ownership agreed and frozen in docs/contracts, decisions logged in docs/decisions.md |
| 25 Sep 2026 | M0.6 M0.4 | Flutter project moved to apps/mobile. Bugs B1 to B6 fixed with tests |

## 5. Scope of the first release

| Included | Next version if time runs out | Later |
|---|---|---|
| Phone login, name and avatar | 2v2 teams | Tournaments and leaderboards |
| Full Ugandan rules engine | Rematch and friends | Cosmetics shop |
| Offline play against bots | Quick chat phrases | Replays and spectating |
| Private rooms shared on WhatsApp | | iOS |
| Quick match for 1v1 and four players | | Custom house rules |
| Server dice, timer, reconnect | | More languages, Kenya and Rwanda |
| Tutorial | | |
| Wallet with MoMo and Airtel deposits | Withdrawals | Paid four player and team tables |
| Paid 1v1 tables | | |
| Free coin tables | | |
| English and Luganda | | |
| Crash reporting and analytics | | |

We are not building free text chat or desktop and web builds for the first release.

## 6. Technical design

### One rules engine for app and server

The Ugandan rules are complicated. If the app and the server each had their own copy, they would drift apart and players would see disputed moves. So the rules live in one pure Dart package, packages/ludo_engine, with no Flutter or network code.

The app uses it to highlight legal moves, run bot games offline and animate moves. The server uses the same package to roll the dice, check every move and send the result to all players. The server always has the final say.

This is the main reason the backend is written in Dart.

### Components

| Part | Choice | Reason |
|---|---|---|
| App | Flutter, Android first, minimum SDK 23 | Existing code base |
| App state and routing | Riverpod and go_router | Standard, and handles invite links |
| Board | CustomPainter with simple animations | Light enough for low end phones |
| Game server | Dart with shelf and web sockets | Shares the rules engine |
| Database | PostgreSQL | Users, matches, move logs, wallet ledger |
| Cache and queues | Redis | Live rooms, matchmaking, reconnects |
| Login | Phone OTP through Firebase Auth or Africa's Talking | Phone numbers are how people here identify, and they match mobile money later |
| Notifications, crashes, analytics | Firebase | Free and well supported |
| Payments | MTN MoMo and Airtel Money APIs, directly or through Flutterwave, Pesapal, Relworx or Yo! Payments | A payment company is quicker to set up, direct integration is cheaper at volume |
| Hosting | One virtual machine plus managed Postgres | A turn based game needs little computing power |

We looked at Firebase as the whole backend, but the phone would decide the dice, which cannot be trusted with money. Nakama and Colyseus are both good game servers, but each would mean writing the rules a second time in another language.

### Messages between app and server

Messages are JSON over a secure web socket. Each one carries a sequence number so a reconnecting phone can catch up.

| Direction | Message | Contents |
|---|---|---|
| App to server | join_room | Room code, login token and stake for paid tables |
| Server to app | room_state | Seats, rules, board, whose turn, time left |
| App to server | roll | Nothing |
| Server to app | dice | Two values, proof and legal moves |
| App to server | move | The pieces and dice chosen |
| Server to app | state_patch | Moves, captures, next turn |
| Server to app | game_over | Final ranking and wallet change |

Each turn should use under 2 KB, keeping a full game under 200 KB.

### Database tables

| Table | Holds |
|---|---|
| users | Phone, display name, avatar, language, date of birth, verification status |
| friendships | Pairs of users and status |
| rooms | Code, mode, rule settings, owner, status |
| matches | Mode, times, dice seed and its hash, stake, our share |
| match_players | Player, colour, seat, whether a bot, finishing place |
| moves | Every move in order, for replays and disputes |
| accounts and ledger_entries | Double entry ledger for wallet balances, stakes, pots, our share and coins |
| payments | Every deposit and withdrawal, with provider reference and status |

### Repository layout

| Folder | Contents |
|---|---|
| apps/mobile | The Flutter app, moved from the current lib folder |
| packages/ludo_engine | The rules engine and its tests |
| server | Game server and API |
| docs | Rule diagrams and records of technical decisions |
| .github/workflows | CI |

## 7. Design

### Principles

1. Portrait layout, playable with one thumb. Everything touched during a turn sits in the bottom third of the screen.
2. The game teaches the rules. Legal moves always light up and illegal ones cannot be selected.
3. It must run smoothly on a phone with 2 GB of memory, install under 30 MB and play on 3G.
4. It should look and sound Ugandan.

### Game screen

The board fills the screen width. Each player's card sits at the board corner next to their home, with a ring counting down their time. The two dice and the roll button sit at the bottom, with quick chat just below.

### Choosing a move with two dice

This is the hardest part of the interface to get right.

1. After the roll, every piece that can move lights up.
2. Tapping a piece shows where it would land with the first die, the second die and both together.
3. Tapping one of those spots makes the move. If a die is left, repeat.
4. When only one sequence of moves is possible, the game plays it after half a second.
5. An undo button stays available until the last die is used.

### Blocks and captures

A block shows stacked pieces with a count and a bar across the track. When an opponent rolls a double 6 and can reach a block, the bar cracks, which teaches the rule. A captured piece flies home with a short sound, in under a second.

### Look and feel

We will replace the default purple theme. The standard board should be clean with strong contrast. Themes based on local textiles such as bark cloth and kitenge can be sold as cosmetics. Each colour also gets a shape on its pieces so colour blind players can tell them apart.

### Language

The app launches in English and Luganda. Luganda text must be written and checked by native speakers. Quick chat uses ready made phrases in both languages, with no free typing in the first release.

### First time players

Sign up with phone number, code, name and avatar in under a minute. Then a three minute tutorial against a bot walks through each Ugandan rule once: leaving home with a 6, combining dice, making a block, breaking a block with a double 6, and finishing exactly. Players who know the rules can skip it. Finishing the tutorial earns coins.

### Core screens for Figma

1. Login with phone number
2. Profile setup
3. Home: play now, play with friends, practice, coins, daily reward
4. Choose mode and table: free, coins or paid stake
5. Private room lobby with WhatsApp share
6. Searching for players
7. Game
8. Results with rematch and share
9. Wallet: balance, deposit, history and limits

## 8. Growth

1. Every private room creates a link, and every result screen can be shared as an image. Both the inviter and the new player get coins when an invite brings someone in.
2. Start on campuses such as Makerere, Kyambogo, MUBS and Ndejje, with student ambassadors and hall tournaments.
3. Make exciting moments, like breaking a block with a double 6, easy to share on TikTok and WhatsApp Status.
4. Run Arena nights at places where people already play Ludo.
5. Lead with the rules: this is Ludo the way we play it.
6. Keep players coming back with daily rewards, weekly tournaments, streaks and rematches.
7. Mention low data use in the store listing.

## 9. Other revenue

Coins are earned through daily rewards, wins, the tutorial and invites. They pay for entry to free coin tables.

Rewarded ads give coins or a second chance. We will not show ads during a game.

Dice, piece and board designs can be bought with coins or from the wallet.

## 10. Wallet and paid play

### How money moves

1. A player deposits with MTN MoMo or Airtel Money. The provider confirms the payment through a callback, and only then is the wallet credited.
2. Joining a paid table moves the stake from the player's wallet into a pot account for that match.
3. When the game ends, the server moves our share to our revenue account and the rest to the winner's wallet.
4. If a game is abandoned before it starts, every stake goes back to its owner.
5. Every movement is a pair of ledger entries, so balances can always be rebuilt from the ledger.

### Payout calculation

The tax rates are settings, not fixed in code. Under current Ugandan rules our share is taxed at 30 percent and 15 percent is withheld from the winner's net gain. A 1v1 game at UGX 5,000 each with a 12 percent share settles like this:

| Item | UGX |
|---|---|
| Pot | 10,000 |
| Our share at 12 percent | 1,200 |
| Paid to winner before tax | 8,800 |
| Winner's net gain | 3,800 |
| 15 percent withheld from the net gain | 570 |
| Winner receives | 8,230 |
| 30 percent tax on our share | 360 |
| We keep | 840 |

### Table rules

Paid play starts with 1v1 only, because four player and team games make it easy for friends to gang up on a stranger. There are no bots at paid tables. Friends are not matched against each other in paid queues. Tables are UGX 1,000, 2,000, 5,000, 10,000, 20,000 and 50,000, and our share is a setting between 10 and 15 percent.

### Player protection

The minimum age for paid tables is a setting, currently 25 to match Ugandan law. Players can set deposit limits and exclude themselves for a period. The wallet screen shows session time and net result for the day.

### Builds

Google Play does not allow mobile money deposits for stakes in a Play Store app without Google's approval, and purchases of digital items there must use Google Play Billing. So the app has two build flavours from one code base: a Play Store build with free and coin play only, and a full build with the wallet, downloaded from our website. Paid features are switched on by the server, not by the app version.

### Reconciliation

Every day the ledger is checked against the provider statements. Any difference is flagged for a person to review. Large withdrawals also wait for a person to approve them.

## 11. Fairness and cheating

1. The server rolls the dice and decides every move. The app only displays results.
2. At the start of each match the server publishes a fingerprint of a secret seed. Every roll comes from that seed, a seed from the player's phone and the roll number. At the end the seed is revealed, so anyone can check every roll with the Verify button on the results screen.
3. Every move is logged to settle disputes.
4. We watch for collusion at paid tables: shared devices, networks or mobile money numbers, the same players meeting repeatedly, and players who avoid obvious captures.
5. Login codes, room creation and matchmaking have rate limits.
6. Bots are always labelled as bots.

## 12. Targets for the first release

| Measure | Target |
|---|---|
| Crash free sessions | 99 percent |
| Games that reach the end | 80 percent |
| Successful reconnects | 90 percent |
| Players back the next day | 35 percent |
| Players back after a week | 15 percent |
| Games per daily player | 3 |
| Tutorial completion | 70 percent |
| Data per game | Under 200 KB |

## 13. How we work

We use trunk based development. Everyone commits to main in small steps, and main must always build and pass tests.

1. Unfinished features stay hidden behind a setting until they are ready.
2. CI runs formatting, flutter analyze, flutter test and the engine and server tests on every push.
3. A task is done when it has tests, works on a low end Android phone, has its text translated, and the tracker in section 4 is updated.
4. Rule changes go into section 2 first, then code, then tests.
5. Passwords and keys never go into the repo.
6. Important technical decisions get a short line in docs/decisions.md, and shared interfaces are written down in docs/contracts before they are built.
7. Releases are tagged on main, for example v0.1.0.

Commit messages start with the task ID when there is one, for example `M1.2 add legal move generation for two dice`.

### CI and CD

Three GitHub Actions workflows live in .github/workflows. Each one checks which projects exist, so they work both before and after the repo is split into apps/mobile, packages/ludo_engine and server.

| Workflow | Runs on | What it does |
|---|---|---|
| ci.yml | Every push to main and every pull request | Formats, analyzes and tests the app, the engine and the server. The engine fails below 95 percent coverage. Server tests run against real Postgres and Redis. Every push to main also builds a release APK and keeps it for 14 days in the run's artifacts, for testing on real phones |
| release-android.yml | Tags starting with v, for example v0.1.0 | Builds the signed APK and app bundle, attaches the APK to a GitHub release for the website download, and uploads the bundle to Play internal testing once the Play secrets are set |
| deploy-server.yml | After CI passes on main, and on tags | Builds the server Docker image, pushes it to GitHub's container registry and deploys it over SSH. Main goes to staging, tags go to production. It skips quietly until server/Dockerfile exists |

Dependabot checks for package and action updates weekly.

To release, make sure CI is green on main, then run `git tag v0.1.0` and `git push origin v0.1.0`.

### CI and CD settings

Set these in GitHub under Settings, then Secrets and variables, then Actions. Create two environments, staging and production, under Settings, then Environments, and turn on required reviewers for production so every production deploy waits for approval.

| Name | Kind | Scope | Where to get it |
|---|---|---|---|
| ANDROID_KEYSTORE_BASE64 | Secret | production | Create an upload key with keytool, then base64 encode the .jks file |
| ANDROID_KEYSTORE_PASSWORD | Secret | production | The store password chosen when creating the key |
| ANDROID_KEY_ALIAS | Secret | production | The alias chosen when creating the key |
| ANDROID_KEY_PASSWORD | Secret | production | The key password chosen when creating the key |
| PLAY_SERVICE_ACCOUNT_JSON | Secret | production | A Google Cloud service account given release access in Play Console, under API access |
| ANDROID_PACKAGE_ID | Variable | repository | The final package id, once decided in M0.5 |
| DEPLOY_HOST | Secret | staging and production | IP or host name of each server |
| DEPLOY_USER | Secret | staging and production | The SSH user on that server |
| DEPLOY_SSH_KEY | Secret | staging and production | A private key whose public half is in that user's authorized_keys |

Server keys for MoMo, Airtel and Firebase do not go into GitHub. They live in /opt/arena/.env on each server, next to the compose file the deploy uses.

Keep the upload keystore backed up outside GitHub. Losing it means the app can no longer be updated on the Play Store.

### Running the app

```
cd apps/mobile
flutter pub get
flutter run
flutter test
flutter build apk
```

## 14. Other decisions still needed

| No. | Decision |
|---|---|
| D1 | Final brand name and domain, which sets the permanent Android package id |
| D2 | Personal or organisation Google Play account |
| D3 | Who writes and checks the Luganda text |
| D4 | Payment provider: direct MTN and Airtel APIs or a payment company |

## 15. Terms

| Term | Meaning |
|---|---|
| Block | Two or more pieces of one colour on one square |
| Release | Moving a piece out of home with a 6 |
| Home column | The five coloured squares before the centre |
| Our share | The percentage of each paid pot we keep |
| Pot | The stakes held for a match until it ends |
| Gross gaming revenue | Stakes minus winnings paid out, which for us is our share |

## 16. Sources

Uganda approves harmonised 30 percent tax on betting and gaming, iGaming Business
https://igamingbusiness.com/finance/tax/uganda-approves-harmonised-tax-betting-gaming/

Google Play real money gambling policy
https://support.google.com/googleplay/android-developer/answer/9877032

MTN MoMo developer API
https://momo.mtn.com/api/

Uganda payment options, Boldrails
https://boldrails.com/payments/uganda

Real money Ludo in Nigeria, Carry1st and MPL
https://www.carry1st.com/blog/can-you-earn-money-playing-ludo-online-in-nigeria-in-2025
https://www.mpl.ng/

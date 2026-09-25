# Arena

Arena is a mobile app for playing Ugandan Ludo online with friends, strangers and bots. We are building for Android first, in Flutter.

The game is free at launch. Real money staking comes later, and only once we have a legal route to run it.

This file is the main reference for the team. The milestone tracker in section 4 is updated with every commit.

## 1. The product

### Who it is for

Our main players are young adults aged 18 to 35 in Kampala and other towns. Most use Android phones and watch their data. Once staking arrives, we also expect players who already use betting apps and want a game where skill matters.

### How people play

| Way to play | Description |
|---|---|
| Friends | Create a private room and share the link or code on WhatsApp |
| Quick match | Join a queue and get matched with other players |
| Practice | Play against the computer |

Game modes are 1v1, four player free for all, and 2v2 teams.

### How we make money

In the free phase players earn and spend coins that can never be cashed out. Revenue comes from rewarded ads and cosmetic items.

In the paid phase players stake between UGX 1,000 and UGX 50,000 through MTN MoMo or Airtel Money, and we keep 10 to 15 percent of each pot. Bots never sit at a paid table.

### Why people will choose Arena

1. It plays by our rules. Ludo King and Ludo Club use the international single die rules. Nobody serves the Ugandan game properly.
2. It suits local phones and networks: small download, low data use, and games that survive a dropped connection.
3. It feels local, with Luganda in the app and invites that go straight to WhatsApp.
4. The dice can be checked. Every roll can be verified after the game, so players can trust the results before any money is involved.

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

The Flutter project is named `arena` and lives at github.com/carlan2023/Arena.

| File | What it does now |
|---|---|
| lib/main.dart | Routes for login, home, register and board, plus the theme |
| lib/screens/login_screen.dart | Validates the form but never calls the auth service |
| lib/screens/register_screen.dart | Calls the stub auth service, then opens home |
| lib/screens/home_screen.dart | Shows a welcome message and nothing else. The board cannot be reached from the app |
| lib/screens/board_screen.dart | Shows the board and dice, with separate layouts for narrow and wide screens |
| lib/widgets/ludo_board.dart | Draws a 15 by 15 grid of colours. No track, no pieces |
| lib/widgets/dice_widget.dart | One die that rolls on tap |
| lib/services/auth_service.dart | Returns a made up user after one second |
| test/widget_test.dart | Still the default Flutter counter test, which fails |

### Known bugs

| No. | Bug |
|---|---|
| B1 | The dice image for 6 is spelled assets/dice6).png, so the app crashes on every 6 |
| B2 | The white inner squares of each home never show, because the corner colour rules run first |
| B3 | The home arm colours do not line up with the corner colours |
| B4 | Login never calls the auth service and the loading state never changes |
| B5 | The link back to login on the register screen calls pop, but there is no screen to go back to |
| B6 | The widget test is the Flutter counter template |
| B7 | The Android package is still com.example.ludo_stake. It must change before the first Play Store upload, since it can never change afterwards |
| B8 | .github/copilot-instructions.md describes an older version of the project |

We keep the project structure, the dice images and the folder layout. The email login will be replaced by phone number login. The grid board will be replaced by a drawn board driven by a track model, and the single die by two dice rolled on the server.

## 4. Milestones and progress

### Target

The public Android release is due by 31 December 2026, with mid January 2027 as the fallback. The team is two developers, usually working one at a time.

Google Play requires new personal developer accounts to run a closed test with at least 12 testers for 14 days before going live. So closed testing must start by 14 December, unless we register as an organisation.

### How to keep this tracker updated

With every commit to main:

1. Change the status of any task the commit moves forward. Use Not started, In progress, or Done.
2. Put the short commit hash in the Commit column when a task is done.
3. Add one line to the progress log with the date, hash and a plain description.
4. Update the milestone summary if the overall status changed.

### Milestone summary

| Milestone | Dates | Status |
|---|---|---|
| M0 Foundations | 28 Sep to 9 Oct 2026 | In progress |
| M1 Rules engine and offline play | 12 Oct to 6 Nov 2026 | Not started |
| M2 Online private rooms | 9 Nov to 27 Nov 2026 | Not started |
| M3 Matchmaking and polish | 30 Nov to 11 Dec 2026 | Not started |
| M4 Closed beta | 14 Dec to 28 Dec 2026 | Not started |
| Release | 29 Dec to 31 Dec 2026 | Not started |

### M0 Foundations

Done when the rules are signed off, the known bugs are fixed, the repo is restructured and CI is running.

| ID | Task | Status | Commit |
|---|---|---|---|
| M0.1 | Write the project README | Done | 163efbe |
| M0.2 | Draft board layout and dice widget | Done | 0485f45 |
| M0.3 | Decide rules R1 to R8 | Not started | |
| M0.4 | Fix bugs B1 to B8 | Not started | |
| M0.5 | Choose the final brand name and Android package id | Not started | |
| M0.6 | Restructure the repo into apps/mobile, packages/ludo_engine and server | Not started | |
| M0.7 | Set up GitHub Actions for format, analyze and tests | Not started | |
| M0.8 | Register the Google Play developer account | Not started | |
| M0.9 | Wireframe the eight core screens in Figma | Not started | |

### M1 Rules engine and offline play

Done when a full game can be played offline against bots, with every rule in section 2 covered by tests.

| ID | Task | Status | Commit |
|---|---|---|---|
| M1.1 | Game state model: track, home columns, pieces, blocks | Not started | |
| M1.2 | Legal move generation for two dice | Not started | |
| M1.3 | Block rules, including block capture | Not started | |
| M1.4 | Exact finish and win detection | Not started | |
| M1.5 | Rule settings for R1 to R8 | Not started | |
| M1.6 | Unit tests covering every test case in section 2, with at least 95 percent coverage | Not started | |
| M1.7 | New board drawn with CustomPainter | Not started | |
| M1.8 | Pieces, move highlights and animations | Not started | |
| M1.9 | Two dice tray and move selection | Not started | |
| M1.10 | Easy and normal bots | Not started | |
| M1.11 | Pass and play on one phone for internal testing | Not started | |

### M2 Online private rooms

Done when two to four people can finish a game online from a shared WhatsApp link.

| ID | Task | Status | Commit |
|---|---|---|---|
| M2.1 | Dart game server with WebSocket rooms | Not started | |
| M2.2 | Server dice with verifiable rolls | Not started | |
| M2.3 | Phone number login with OTP | Not started | |
| M2.4 | Create room, join by code or link | Not started | |
| M2.5 | Turn timer and automatic moves | Not started | |
| M2.6 | Reconnect within 60 seconds | Not started | |
| M2.7 | Save match history and move log to Postgres | Not started | |
| M2.8 | Staging server running | Not started | |

### M3 Matchmaking and polish

Done when strangers can find a game within 20 seconds and the app is ready for testers.

| ID | Task | Status | Commit |
|---|---|---|---|
| M3.1 | Quick match queue for 1v1 and four players | Not started | |
| M3.2 | Bots fill empty seats in free games after 20 seconds | Not started | |
| M3.3 | Profiles and avatars | Not started | |
| M3.4 | Coins and daily reward | Not started | |
| M3.5 | Luganda translation | Not started | |
| M3.6 | Sound and vibration | Not started | |
| M3.7 | Interactive tutorial | Not started | |
| M3.8 | 2v2 teams, which moves to January if time runs short | Not started | |

### M4 Closed beta and release

| ID | Task | Status | Commit |
|---|---|---|---|
| M4.1 | Closed test with at least 12 testers for 14 days | Not started | |
| M4.2 | Crash free sessions at 99 percent or higher | Not started | |
| M4.3 | Store listing, privacy policy and data safety form | Not started | |
| M4.4 | Production release in Uganda | Not started | |

### After release

| Version | When | Focus |
|---|---|---|
| 1.1 | January 2027 | 2v2 if it slipped, friends list, rematch, quick chat, shareable results |
| 1.2 | February and March 2027 | Coin tournaments, leaderboards, seasons, cosmetics shop, iOS |
| Paid play preparation | From January 2027 | Legal opinion, licence route, KYC, wallet, payment partner |
| Paid play | Q3 2027 at the earliest, and only with a licence route | 1v1 paid tables first |

### Progress log

| Date | Commit | Change |
|---|---|---|
| | 8a00a66 | First commit, Flutter project created |
| | fb201ea | Login, register and home screens added |
| | 0485f45 | Board layout and dice widget |
| | 98ac4dc | Merged main |
| 25 Sep 2026 | 163efbe | Project README added |

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
| Coins that cannot be cashed out | | |
| English and Luganda | | |
| Crash reporting and analytics | | |

We are not building free text chat, paid play or desktop and web builds for the first release.

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
| Database | PostgreSQL | Users, matches, move logs, coin ledger |
| Cache and queues | Redis | Live rooms, matchmaking, reconnects |
| Login | Phone OTP through Firebase Auth or Africa's Talking | Phone numbers are how people here identify, and they match mobile money later |
| Notifications, crashes, analytics | Firebase | Free and well supported |
| Hosting | One virtual machine plus managed Postgres | A turn based game needs little computing power |

We looked at Firebase as the whole backend, but the phone would decide the dice, which cannot be trusted with money. Nakama and Colyseus are both good game servers, but each would mean writing the rules a second time in another language.

### Messages between app and server

Messages are JSON over a secure web socket. Each one carries a sequence number so a reconnecting phone can catch up.

| Direction | Message | Contents |
|---|---|---|
| App to server | join_room | Room code and login token |
| Server to app | room_state | Seats, rules, board, whose turn, time left |
| App to server | roll | Nothing |
| Server to app | dice | Two values, proof and legal moves |
| App to server | move | The pieces and dice chosen |
| Server to app | state_patch | Moves, captures, next turn |
| Server to app | game_over | Final ranking and coins won or lost |

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
| accounts and ledger_entries | Double entry ledger for coins, reused later for money |

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
4. Choose mode and coin entry
5. Private room lobby with WhatsApp share
6. Searching for players
7. Game
8. Results with rematch and share

## 8. Growth

1. Every private room creates a link, and every result screen can be shared as an image. Both the inviter and the new player get coins when an invite brings someone in.
2. Start on campuses such as Makerere, Kyambogo, MUBS and Ndejje, with student ambassadors and hall tournaments.
3. Make exciting moments, like breaking a block with a double 6, easy to share on TikTok and WhatsApp Status.
4. Run Arena nights at places where people already play Ludo.
5. Lead with the rules: this is Ludo the way we play it.
6. Keep players coming back with daily rewards, weekly tournaments, streaks and rematches.
7. Mention low data use in the store listing.

## 9. Revenue in the free phase

Coins are earned through daily rewards, wins, the tutorial and invites, and can also be bought. They pay for entry to coin tables. Coins can never be exchanged for money or anything of cash value. That keeps the free app outside gaming law and within Google Play policy.

Rewarded ads give coins or a second chance. We will not show ads during a game.

Dice, piece and board designs can be bought with coins or money. Any purchase inside the Play Store app must go through Google Play Billing, so mobile money top ups wait for the paid phase.

If a sponsor offers prizes for a tournament, check with the gaming board first, because prize competitions may need a permit.

## 10. The paid phase

This is research for planning. A Ugandan gaming lawyer must confirm it before any money moves.

### Staked Ludo is almost certainly gaming

The Lotteries and Gaming Act 2016 covers games that involve chance, and dice are chance even when skill matters. We should assume a licence from the National Lotteries and Gaming Regulatory Board is needed. The first step is a written legal opinion.

### New licences are frozen

Since 2019 the government has told the board not to issue new gaming licences. That leaves three routes:

1. Partner with a company that already holds a licence. We provide the game and they run the money side. This is the fastest route.
2. Buy a company that holds a licence.
3. Be ready to apply when the freeze ends.

For reference, fees for Ugandan applicants are about UGX 25 million to apply and UGX 25 million for the licence, with foreign applicants paying double. The minimum paid up capital for a general betting licence is around UGX 250 million, and licences are renewed every calendar year.

The legal gambling age in Uganda is 25. Licensed operators also need NITA-U certification of their systems, approval of every advert, responsible gaming controls and anti money laundering reporting.

### Tax from July 2026

Operators pay 30 percent of their gross gaming revenue, which for us is our share of each pot. A further 15 percent is withheld from players' net winnings before payout.

A 1v1 game at UGX 5,000 each with a 12 percent share works out like this:

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

A tax adviser should confirm how the withholding is calculated.

### Distribution

Google Play only allows real money gambling apps in approved countries, with a local licence and Google's approval. We should plan for two builds: the free app on Play Store and the paid version downloaded from our own website. The paid version must confirm the player is 25 or older and verify their identity before the wallet opens.

### Payments

Use the MTN MoMo and Airtel Money APIs directly, or go through a payment company such as Flutterwave, Pesapal, Relworx or Yo! Payments. A payment company is quicker to set up and direct integration is cheaper at volume. The wallet uses the same double entry ledger as the coins, is reconciled daily against provider statements, and large withdrawals are checked by a person.

### Compliance

1. Identity checks with national ID and a selfie, verified against NIRA
2. Age check for 25 and over
3. Deposit and loss limits, session reminders, self exclusion and cool off periods
4. Transaction monitoring and reporting to the Financial Intelligence Authority where required
5. Registration with the Personal Data Protection Office under the Data Protection and Privacy Act 2019. This applies from the free phase, since we store phone numbers
6. An information security baseline in line with ISO 27001, which will make NITA-U certification and partner checks easier

### Paid game design

Paid play starts with 1v1 only, because four player and team games make it easy for friends to gang up on a stranger. There are no bots at paid tables. Friends are not matched against each other in paid queues. Tables are UGX 1,000, 2,000, 5,000, 10,000, 20,000 and 50,000, with our share between 10 and 15 percent.

Kenya and Rwanda each have their own regulator and taxes, so each would be a separate licence project.

## 11. Fairness and cheating

1. The server rolls the dice and decides every move. The app only displays results.
2. At the start of each match the server publishes a fingerprint of a secret seed. Every roll comes from that seed, a seed from the player's phone and the roll number. At the end the seed is revealed, so anyone can check every roll with the Verify button on the results screen.
3. Every move is logged to settle disputes.
4. We watch for collusion: shared devices, networks or mobile money numbers, the same players meeting repeatedly, and players who avoid obvious captures.
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
6. Important technical decisions get a short note in docs/adr.
7. Releases are tagged on main, for example v0.1.0.

Commit messages start with the task ID when there is one, for example `M1.2 add legal move generation for two dice`.

### Running the app

```
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
| D4 | Who leads the legal opinion and talks with licensed partners, and by when |

## 15. Terms

| Term | Meaning |
|---|---|
| Block | Two or more pieces of one colour on one square |
| Release | Moving a piece out of home with a 6 |
| Home column | The five coloured squares before the centre |
| Our share | The percentage of each paid pot we keep |
| Gross gaming revenue | Stakes minus winnings paid out, which for us is our share |
| KYC | Checking a player's identity and age |
| NLGRB | National Lotteries and Gaming Regulatory Board |

## 16. Sources

Uganda gambling laws and market outlook 2026, Altenar
https://altenar.com/blog/gambling-laws-and-regulations-in-uganda-licensing-compliance-and-market-reality/

Uganda's gambling sector in 2025, PML Daily
https://pmldaily.com/sports/2025/10/ugandas-gambling-sector-in-2025-a-definitive-legal-and-regulatory-guide-for-operators.html

Uganda approves harmonised 30 percent tax on betting and gaming, iGaming Business
https://igamingbusiness.com/finance/tax/uganda-approves-harmonised-tax-betting-gaming/

Uganda gaming board 2026 licence renewals, iGamingToday
https://www.igamingtoday.com/strict-new-rules-announced-as-uganda-gambling-board-begins-2026-license-renewals/

NLGRB licensing process
https://lgrb.go.ug/licensing-process/

Lotteries and Gaming Act 2016
https://ulii.org/akn/ug/act/2016/7/eng@2023-12-31

Google Play real money gambling policy
https://support.google.com/googleplay/android-developer/answer/9877032

MTN MoMo developer API
https://momo.mtn.com/api/

Uganda payment options, Boldrails
https://boldrails.com/payments/uganda

Real money Ludo in Nigeria, Carry1st and MPL
https://www.carry1st.com/blog/can-you-earn-money-playing-ludo-online-in-nigeria-in-2025
https://www.mpl.ng/

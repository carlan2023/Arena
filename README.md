# Arena: Ugandan Ludo, online

> Working name: **Arena**. Mobile-first app where Ugandans play Ludo by the rules they grew up with, against friends, strangers and bots. Free to play at launch; licensed real-money stakes are a later phase.

This README is the single source of context for the team. Read sections 1 to 4 before writing any code. Section 5 onward is reference.

---

## Contents

1. [Product in one page](#1-product-in-one-page)
2. [Ugandan Ludo rules (the spec)](#2-ugandan-ludo-rules-the-spec)
3. [Where the code is today](#3-where-the-code-is-today)
4. [Milestones to MVP](#4-milestones-to-mvp)
5. [MVP scope](#5-mvp-scope)
6. [Architecture](#6-architecture)
7. [Design direction and UX](#7-design-direction-and-ux)
8. [Growth strategy](#8-growth-strategy)
9. [Monetisation (free phase)](#9-monetisation-free-phase)
10. [Real-money phase: legal, payments, risk](#10-real-money-phase-legal-payments-risk)
11. [Trust, fairness and anti-cheat](#11-trust-fairness-and-anti-cheat)
12. [Metrics](#12-metrics)
13. [Engineering workflow](#13-engineering-workflow)
14. [Open questions](#14-open-questions)
15. [Glossary](#15-glossary)
16. [Sources](#16-sources)

---

## 1. Product in one page

**What it is.** A mobile-first online Ludo game built on the Ugandan variant: two dice, blocks that act as walls, block captures that need double sixes, exact finish, no safe squares. Global Ludo apps (Ludo King, Ludo Club) play the international single-die rules, so the rules themselves are our first differentiator.

**Who it is for.**
- Primary: young urban adults, 18 to 35, in Kampala and other towns. Android, data-conscious, social and competitive.
- Secondary: people already on betting apps looking for a game where skill matters. They become the core audience once staking launches.

**How people play at MVP.**
- Online with friends: private room, share a link or code on WhatsApp.
- Online with strangers: quick-match queue.
- Versus computer: bots for practice and to fill empty seats in free games.
- Modes: 1v1, 4-player free-for-all, 2v2 teams.

**Business model, in two phases.**
1. **Free phase (MVP):** virtual coins that can never be cashed out, rewarded ads, cosmetics. Builds the player base and proves the game.
2. **Real-money phase (later):** players stake UGX 1,000 to 50,000 per game via MTN MoMo and Airtel Money; the platform keeps a 10 to 15% rake. Only possible with a licence route (see section 10). **Bots and AI seats never play in money games.**

**Why we can win.**
- Our rules, not the international ones. Nobody serves this variant well.
- Built for Ugandan phones and networks: small download, low data per game, survives a dropped connection.
- Local identity: Luganda UI, local look and feel, WhatsApp-native invites.
- Trust: provably fair dice from day one, so the "the app is rigged" complaint has a real answer before money is involved.

---

## 2. Ugandan Ludo rules (the spec)

This is the source of truth for the rules engine. Any rule change goes through a PR to this section first, then code. Items marked **OPEN** need a decision from the product owner (Allan) before the engine is final; the engine should expose each one as a config flag so we can switch without rewrites.

### 2.1 Board and pieces

- Standard cross-shaped board: 52 shared track squares, one start square per colour, a 5-square home column per colour, then the finish (centre).
- A piece travels 51 track squares plus 5 home column squares plus 1 step into the finish = **57 steps** from its start square.
- 4 colours, 4 pieces each. Turn order is clockwise.

### 2.2 Dice

- Each turn a player rolls **two dice**.
- Each die value can be used on a different piece, or **both values combined on one piece** (roll 3 and 5: move one piece 3 and another 5, or one piece 8).
- A combined move is played as two steps (first die, then second die). Each intermediate landing must itself be legal (you cannot combine to jump a block you could not pass one die at a time). **OPEN:** confirm.
- **Double 6 gives an extra roll** after the moves are played.
- **OPEN:** does rolling double 6 three times in a row forfeit the turn (common in other variants)?
- **OPEN:** do other doubles (1-1 to 5-5) give anything besides moving a block together (2.6)?

### 2.3 Leaving home

- A piece leaves home onto its start square when **either die shows a 6**. That 6 is consumed by the release.
- The other die may move any piece, including the one just released.
- Double 6 can release two pieces, or release one and move 6, then the extra roll follows.

### 2.4 Movement obligations

- **A player must move if any legal move exists.** Passing is not allowed while a legal move exists.
- **Capturing is optional:** if several legal moves exist, the player may choose a non-capturing one.
- **OPEN:** if both dice can be used, must the player use both? If only one can be used, may they pick which? Proposed default: use both when possible; if only one is usable, the player picks.
- If no legal move exists for either die, the turn passes automatically.

### 2.5 Capture

- Landing exactly on a single opponent piece sends it back home.
- **No bonus** for capturing (no extra roll, no extra steps).
- **No safe squares.** Start squares are not safe either. The only protection is a block.

### 2.6 Blocks

A block is **2 or more pieces of the same colour on one square**.

- **Opponents cannot pass a block.** An opponent piece behind it must wait or use its dice on other pieces.
- **Own pieces:** your own pieces cannot jump over your block either; they may only **land exactly on it** (joining it, making it bigger). Interpretation of: "Own pieces of the same colour can pass over if the dice provide a figure that can land exactly on the block." **OPEN:** confirm this reading, or whether an exact landing lets the piece continue past on the other die.
- **A block moves together on a double:** e.g. 4-4 lets the whole block move 4 squares as one unit. **OPEN:** does a 2-piece block on 4-4 move 4 (one die) or 8 (both dice)?

### 2.7 Capturing a block

- To capture a **2-piece block**, the attacker must first roll **double 6**. That earns the extra roll; on the extra roll, a die (or combined dice) must land the attacking piece **exactly** on the block.
- If the attacker's distance roll is longer than the distance to the block, the attacker **may choose to pass the block** (the double 6 lifts the wall for that attacker for that turn).
- A **3-piece block** needs **three sixes**, a **4-piece block** needs **four sixes**, plus the exact distance. **OPEN:** are these sixes counted across the chain of rolls in one turn (6-6 then a roll containing a 6), and does the final roll that supplies the distance count toward the sixes?
- When a block is captured, **every piece in the block goes home**.

### 2.8 Finishing

- **Exact roll required.** A piece 4 steps from the finish can use a 4, or 1+3 split across dice, but not a 5. An overshooting die must be used elsewhere or is lost if nothing else is legal.
- A player wins when all 4 pieces are in the finish.

### 2.9 Game modes

| Mode | Seats | Win condition |
|---|---|---|
| 1v1 | 2 players on opposite colours | First to finish all 4 pieces |
| Free-for-all | 4 players | First to finish; the rest keep playing for 2nd and 3rd (**OPEN:** or end immediately?) |
| 2v2 teams | Partners sit opposite | **OPEN:** team wins when both partners finish, or when the first partner finishes? |

**2v2 specifics**
- Partners **can** capture each other: by choice, or when it is the only legal move.
- **OPEN:** can one piece of mine and one of my partner's form a joint block? Proposed default: no, blocks are single-colour.
- **OPEN:** once a player finishes, do they roll for their partner? Proposed default: yes, it keeps them engaged.

### 2.10 Timing (proposed, needed for online play)

- 20 seconds per decision. On timeout the server plays the best legal move automatically.
- 3 consecutive timeouts: in free games a bot takes over the seat; in money games the player forfeits.
- 60-second grace period for reconnecting after a dropped connection.
- Target game length: full game, 15 to 30 minutes.

### 2.11 Worked examples (use as engine test cases)

1. Red has all pieces home, rolls 6 and 3. Red releases a piece with the 6 and moves it 3. Result: piece on start+3.
2. Blue piece is 5 squares behind a red 2-piece block, Blue rolls 4 and 6. Blue cannot use 6 on that piece (would pass the block). Blue may use 4 on it, and 6 elsewhere.
3. Same position, Blue rolls 6-6, then 5 and 2 on the extra roll. Blue moves 5 onto the block; both red pieces go home. Blue may use 2 elsewhere.
4. Same position, Blue rolls 6-6, then 6 and 3. Blue may move 6 past the block (wall lifted), no capture.
5. Yellow piece 4 from finish, rolls 5 and 2. The 5 cannot be used on it. Yellow may move it 2, and must use the 5 on another piece if legal.

---

## 3. Where the code is today

Flutter project (`name: arena`), four commits, repo `github.com/carlan2023/Arena`.

| Area | State |
|---|---|
| `lib/main.dart` | Named routes: `/` login, `/home`, `/register`, `/board`. Purple Material theme. |
| `lib/screens/login_screen.dart` | Form validates but **never calls** `AuthService` (TODO left in). |
| `lib/screens/register_screen.dart` | Calls the stubbed `AuthService.register`, then goes to `/home`. |
| `lib/screens/home_screen.dart` | Placeholder text only. No way to reach `/board` from the UI. |
| `lib/screens/board_screen.dart` | Board plus dice, responsive wide/narrow layout. |
| `lib/widgets/ludo_board.dart` | Static 15x15 `GridView`, colours only. No track model, no pieces. |
| `lib/widgets/dice_widget.dart` | **One** die, random on tap, local `Random()`. |
| `lib/services/auth_service.dart` | Stub, returns fake users after 1s. |
| Tests | `test/widget_test.dart` is Flutter's counter template and will fail. |

### 3.1 Bugs to fix first

1. `dice_widget.dart`: face 6 loads `assets/dice6).png` (typo). The app throws whenever a 6 is rolled.
2. `ludo_board.dart`: the "inner white home" rules sit below the corner rules, so they never run. Homes render as flat colour.
3. `ludo_board.dart`: colours of the home arms do not match the corner homes consistently (e.g. red corner top-left, red arm drawn on the top column). Will be replaced by the track model anyway.
4. `login_screen.dart`: `_isLoading` never changes and the service is never called.
5. `register_screen.dart`: "Already have an account?" calls `Navigator.pop`, but login used `pushReplacementNamed`, so there is nothing to pop.
6. `test/widget_test.dart`: counter test, delete and replace.
7. Android package id still `com.example.ludo_stake`, label `ludo_stake`. Must change before the first Play upload; the id can never change after publishing. Proposed: `ug.arena.ludo` (or matching the final brand's domain).
8. `.github/copilot-instructions.md` describes the old empty state. Update or point it at this README.

### 3.2 What we keep vs replace

- **Keep:** project scaffold, dice assets, folder conventions (`screens/`, `widgets/`, `services/`, `models/`).
- **Replace:** email/password auth with phone-number OTP (section 6.4); `GridView` board with a `CustomPainter` board driven by the track model; single die with a two-dice tray driven by server rolls.

---

## 4. Milestones to MVP

**Target: public Android MVP by 31 December 2026.** Team: 2 developers, mostly one at a time. This is tight (about 13 weeks). The plan front-loads the rules engine because everything else depends on it, and marks the first thing to cut if we slip.

> **Play Store gotcha.** New *personal* Google Play developer accounts must run a closed test with at least 12 testers for 14 continuous days before they can publish to production. Either register the Play account as an **organisation** (needs a D-U-N-S number, which takes time, start now) or start the closed test no later than **14 December**. This date is baked into M4.

| # | Milestone | Dates | Exit criteria |
|---|---|---|---|
| M0 | Foundations | 28 Sep to 9 Oct | Rules in section 2 signed off (all OPEN items closed). Bugs in 3.1 fixed. Repo restructured into `apps/mobile`, `packages/ludo_engine`, `server/`. CI running analyze + tests. Brand name and package id decided. Play developer account registered. Figma wireframes for 8 core screens. |
| M1 | Rules engine + offline play | 12 Oct to 6 Nov | `ludo_engine` implements every rule in section 2 with 95%+ test coverage, all worked examples pass. New board renders pieces, blocks, legal-move highlights, animations. Full game playable **offline vs bots** (easy/normal) and pass-and-play for internal testing. |
| M2 | Online private rooms | 9 Nov to 27 Nov | Game server live on staging. Phone OTP login. Create room, share WhatsApp link, 2 to 4 players join, full online game with server dice, turn timer, reconnect. Match history saved. |
| M3 | Matchmaking + polish | 30 Nov to 11 Dec | Quick-match queue (1v1, 4-player). Bots fill empty seats after 20s in free games. Profiles, avatars, coins, daily reward. Luganda strings. Sounds, haptics, tutorial. **2v2 teams: stretch goal, first to cut to January.** |
| M4 | Closed beta | 14 Dec to 28 Dec | 12+ testers (aim for 50 to 100) on Play closed testing for 14 days. Crash-free sessions 99%+. Top bugs fixed. Store listing, privacy policy, data safety form done. |
| MVP | Public release | 29 to 31 Dec | Production release in Uganda on Google Play. Realistic fallback: mid-January 2027 if M1 slips. |

### After MVP

| Phase | When | Focus |
|---|---|---|
| v1.1 | Jan 2027 | 2v2 (if cut), friends list, rematch, quick-chat in Luganda, shareable game results. |
| v1.2 | Feb to Mar 2027 | Weekly tournaments (coins), leaderboards, seasons, cosmetics shop, iOS build. |
| Money readiness | In parallel from Jan 2027 | Legal opinion, licence route, KYC and wallet ledger design, payment partner (section 10). |
| Real money | Earliest Q3 2027, **only** once a licence route is secured | 1v1 staked games first, then others. |

### Weekly rhythm

- Monday: pick issues for the week from the milestone board.
- Friday: 30-minute demo on a real phone, update milestone status in this README.

---

## 5. MVP scope

**Must have (MVP)**
- Phone-number login (OTP), display name, avatar.
- Rules engine for the full Ugandan variant.
- Offline vs bots (easy, normal).
- Online private rooms via link/code with WhatsApp share.
- Quick match: 1v1 and 4-player.
- Server-authoritative dice and moves, turn timer, auto-move, reconnect.
- Interactive tutorial that teaches blocks and block capture.
- Virtual coins (entry to coin games, daily reward). Never cashable.
- English and Luganda.
- Crash reporting and analytics.

**Should have (MVP if time, else v1.1)**
- 2v2 teams.
- Rematch button, recent opponents, add friend.
- Quick-chat emotes and preset phrases (no free text: no moderation burden).

**Later**
- Tournaments, leaderboards, seasons, cosmetics shop, replays, spectating, iOS, private-room house rules, other local languages, Kenya/Rwanda.

**Not doing**
- Free-text chat at MVP (moderation cost, abuse risk).
- Real money before a licence route exists.
- Desktop/web builds (the scaffolds can stay, no effort spent on them).

---

## 6. Architecture

### 6.1 Overview

```
 Flutter app (Android first)                 Backend (single region)
 +-------------------------+     WSS      +-----------------------------+
 | UI (screens, widgets)   | <----------> | Game server (Dart)          |
 | State (Riverpod)        |              |  - rooms, turns, timers     |
 | ludo_engine (shared)    |              |  - ludo_engine (same code)  |
 | Offline bots            |     HTTPS    |  - crypto RNG, fair dice    |
 +-------------------------+ <----------> | REST API (Dart)             |
                                          |  - auth, profiles, coins    |
                                          +-------------+---------------+
                                                        |
                                           +------------+-----------+
                                           | PostgreSQL | Redis     |
                                           | (truth)    | (rooms,   |
                                           |            |  queues)  |
                                           +------------+-----------+
```

### 6.2 The key decision: one rules engine, written once, in Dart

The Ugandan rules are intricate (two dice, blocks, multi-six block captures). If the rules exist twice, once on the client and once on the server, they will drift and cause "the app cheated me" bugs. So:

- `packages/ludo_engine` is a **pure Dart package**: no Flutter, no I/O, fully deterministic. `GameState`, `legalMoves(state, dice)`, `apply(state, move)`, `RulesConfig` (flags for every OPEN item).
- The **app** uses it to highlight legal moves, run offline bot games and animate predicted moves.
- The **server** uses the same package as the authority: it rolls dice, validates every move, and broadcasts the result.

This is why the recommendation is a **Dart backend**, not Node or Python.

### 6.3 Backend recommendation

| Component | Choice | Why |
|---|---|---|
| Game server | Dart, `shelf` + `shelf_web_socket` (or `dart_frog`) | Shares `ludo_engine`; one language across the team. |
| Database | PostgreSQL (managed) | Users, matches, move logs, coin ledger. Relational, needed for money later. |
| Cache / queues | Redis | Live room state snapshots, matchmaking queues, reconnect tokens. |
| Auth | Phone OTP via Firebase Auth, or Africa's Talking SMS with our own token service | Phone numbers are how Ugandans identify; matches MoMo later. Server verifies tokens. |
| Push | Firebase Cloud Messaging | "Your friend invited you", "your turn". |
| Crash + analytics | Firebase Crashlytics + Analytics | Free, standard. |
| Hosting | One VM (e.g. 2 vCPU) for game + API, managed Postgres | Turn-based games need little CPU. Scale out later with Redis-backed rooms. |

**Alternatives considered**
- **Firebase Realtime DB / Firestore as the game backend:** fastest start, but the client would decide moves and dice. Impossible to make trustworthy for money. Rejected for game logic; fine for push and analytics.
- **Nakama (Heroic Labs):** strong built-ins (matchmaker, leaderboards, wallet), but server logic is in Go/TypeScript/Lua, so the rules would be written twice. Worth revisiting if we outgrow our own server.
- **Colyseus (Node.js):** good room model, but no official Dart client and again two rule implementations.

### 6.4 Client stack

- Flutter, Android first (min SDK 23, test on 2 GB RAM phones).
- State: Riverpod. Routing: go_router (deep links for room invites).
- Board: `CustomPainter` for the board, lightweight widgets for pieces, implicit animations. No game engine (Flame) needed.
- Localisation: `flutter_localizations` + ARB files (`en`, `lg`).
- Deep links: Android App Links, `https://<domain>/r/<roomCode>` opens the room, falls back to the Play Store.

### 6.5 Real-time protocol (sketch)

JSON over WebSocket. Server is always authoritative.

```
client -> server   join_room {roomCode, token}
server -> client   room_state {seats, rules, state, turn, deadline}
client -> server   roll {}
server -> client   dice {values:[6,3], proof, legalMoves:[...]}
client -> server   move {steps:[{piece:2, die:0},{piece:2, die:1}]}
server -> client   state_patch {moves, captures, nextTurn, deadline}
server -> client   game_over {ranking, coinsDelta}
client -> server   emote {id}
```

- Every message carries a sequence number; on reconnect the client sends its last seq and gets a full snapshot.
- Target under 2 KB per turn so a full game uses well under 200 KB of data.

### 6.6 Data model (first cut)

- `users` (id, phone, display_name, avatar, locale, created_at, dob, kyc_status)
- `friendships` (user_a, user_b, status)
- `rooms` (code, mode, rules_config, created_by, status)
- `matches` (id, mode, started_at, ended_at, server_seed_hash, server_seed, stake, rake)
- `match_players` (match_id, user_id, colour, seat, is_bot, finish_rank)
- `moves` (match_id, seq, user_id, dice, steps, created_at): full event log, lets us replay and resolve disputes
- `accounts` + `ledger_entries`: **double-entry ledger even for virtual coins**, so the money phase reuses a tested design

### 6.7 Repository layout (target)

```
apps/mobile/          Flutter app (move current lib/ here)
packages/ludo_engine/ Pure Dart rules engine + tests
server/               Dart game server + REST API
docs/                 Rules diagrams, ADRs (architecture decision records)
.github/workflows/    CI
```

---

## 7. Design direction and UX

### 7.1 Principles

1. **Portrait, one thumb.** Everything the player taps during a turn sits in the bottom third.
2. **The rules teach themselves.** Legal moves are always highlighted; illegal ones never selectable.
3. **Built for real phones.** Smooth on a 2 GB Android, APK under 30 MB, playable on 3G.
4. **Local, not generic.** Ugandan colour, pattern, language and humour.

### 7.2 Game screen layout

```
+----------------------------------+
| [<]  1v1 · Coins 200   [⋮]       |
| (P2 avatar, timer ring)          |
|                                  |
|          BOARD (full width)      |
|                                  |
| (P1 avatar, timer ring)          |
|  [ die ][ die ]   [ ROLL ]       |
|  quick-chat  emotes              |
+----------------------------------+
```

- Board fills the width; player cards at the board's corners next to their homes, each with a countdown ring.
- The two dice sit in a tray at the bottom. Tap ROLL (or shake the phone, optional).

### 7.3 Two-dice move selection (the hardest UX problem)

With two dice, a player may move one piece twice, two pieces once, or release plus move. Proposed flow:

1. After the roll, every piece with a legal move glows.
2. Tap a piece: ghost markers show where it lands with die A, die B and A+B.
3. Tap a ghost to move. If a die remains, repeat.
4. If only one legal move sequence exists, play it automatically after 0.5s.
5. An "undo" button is available until the turn is confirmed (server confirms only after the last die, so undo is free).

### 7.4 Blocks and captures

- A block shows stacked pieces with a count badge and a subtle wall bar across the track.
- When an opponent rolls 6-6 and can attack a block, the wall visibly cracks; that is the teaching moment.
- Capture animation: piece flies home with a short sound. Keep it under 700 ms.

### 7.5 Visual identity

- Replace the default purple Material theme.
- Board themes inspired by local textiles and materials (bark cloth texture, kitenge patterns). Default theme should be clean and high contrast; decorative themes become cosmetics.
- **Colour-blind safe:** each colour also has a shape or icon on its pieces.
- Bold, friendly type; large numerals on dice.

### 7.6 Language and tone

- English and Luganda at launch. Luganda strings written and reviewed by native speakers, not machine-translated.
- Preset quick-chat phrases (friendly banter) in both languages. No free text at MVP.

### 7.7 Onboarding

- Phone number, OTP, name, avatar: under 60 seconds.
- 3-minute interactive tutorial vs a bot that forces each Ugandan rule once: two-dice release, combining dice, a block, a double-six block capture, exact finish. Reward coins at the end.
- Skip button for people who already know the rules.

### 7.8 Core screens (for Figma in M0)

1. Splash / phone login
2. Profile setup
3. Home (Play Now, Play with Friends, Practice vs Bot, coins, daily reward)
4. Mode picker (1v1, 4-player, 2v2, coin entry)
5. Private room lobby (code, share to WhatsApp, seats filling)
6. Matchmaking (searching, bot fallback countdown)
7. Game screen
8. Result screen (rank, coins, rematch, share)

---

## 8. Growth strategy

- **WhatsApp is the loop.** Every private room produces a link; the result screen offers "Share result" as an image. Invites that bring a new player reward both with coins.
- **Campuses first.** Makerere, Kyambogo, MUBS, Ndejje and others: campus ambassadors, hall-vs-hall coin tournaments. Dense social groups, the exact target age.
- **Short video.** A shareable clip or image of dramatic moments (block captured with 6-6) for TikTok and WhatsApp Status.
- **Offline events.** Ludo is already played in bars, stages and hostels. Sponsored "Arena nights" where the physical game is played on phones.
- **Rules as marketing.** "Ludo the way we play it" is the message. Ludo King does not do our blocks.
- **Retention:** daily reward, weekly tournament, streaks, friends list, rematch.
- **Low data promise** in the store listing and marketing.

---

## 9. Monetisation (free phase)

- **Coins:** earned (daily reward, wins, tutorial, invites) and optionally bought. Used as entry fees for coin tables. **Coins can never be converted to money or anything of cash value.** This keeps the free app outside gaming law and inside Google Play policy.
- **Rewarded ads** (AdMob): watch an ad for coins or a second chance. No interstitials during games.
- **Cosmetics:** dice, piece and board skins, bought with coins or real money.
- **Real-money purchases in the Play Store app must go through Google Play Billing** (policy). MoMo top-ups for coins inside the Play build are not allowed; MoMo comes with the money phase.
- **Sponsored prize tournaments** (a brand gives airtime or merchandise): check with NLGRB first, as prize competitions may need a permit.

---

## 10. Real-money phase: legal, payments, risk

This section is research to plan against, not legal advice. A Ugandan gaming lawyer must confirm every point before any money flows.

### 10.1 Is staked Ludo "gaming" in Uganda?

Very likely yes. Uganda's Lotteries and Gaming Act 2016 regulates gaming on games with an element of chance, and dice are chance even when skill matters. Plan on the assumption that staked Arena games need an NLGRB licence. First action: a written legal opinion on classification.

### 10.2 The licence problem

- **New licences have been frozen since 2019.** The government directed NLGRB not to grant new gambling, betting or gaming licences. The practical routes today are:
  1. **Partner with an existing licensee** (Arena supplies the game; the licensed operator runs the money side). Fastest.
  2. **Acquire** a company that already holds a licence.
  3. **Wait** for the freeze to lift, and be application-ready.
- If a licence becomes possible: fees for Ugandan/East African applicants about UGX 25m application + UGX 25m licence (foreign applicants double), minimum paid-up capital around UGX 250m for a general betting licence, annual renewal (calendar year).
- **Minimum age is 25**, not 18. Money games must verify age.
- Licensees need NITA-U certification of their systems, NLGRB approval of adverts, responsible gaming measures (self-exclusion, deposit and time limits), and AML reporting.

### 10.3 Tax (from 1 July 2026)

- **30% tax** on gross gaming revenue (our rake).
- **15% withholding tax** on players' net winnings, deducted by the operator before payout.

Worked example, 1v1 at UGX 5,000 each, 12% rake:

| Item | UGX |
|---|---|
| Pot | 10,000 |
| Rake (12%) | 1,200 |
| Paid to winner before tax | 8,800 |
| Winner's net winnings (8,800 minus own 5,000 stake) | 3,800 |
| 15% withholding on net winnings | 570 |
| Winner receives | 8,230 |
| Gaming tax, 30% of 1,200 | 360 |
| Platform keeps | 840 |

Confirm the withholding base with a tax adviser. With 30% off the rake, pricing toward 15% rake at low stakes may be needed.

### 10.4 Distribution

Google Play only allows real-money gambling apps in approved countries with a local licence and Google approval, and they must not use Play Billing. Plan for **two builds**: the free app on Play Store, and the money-enabled app distributed from our website as a direct APK (unless Google approves Uganda). The money build must ask for age 25+ and KYC before the wallet unlocks.

### 10.5 Payments

- MTN MoMo API (collections and disbursements) and Airtel Money API, directly or through an aggregator (Flutterwave, Pesapal, Relworx, Yo! Payments and similar).
- An aggregator is faster to integrate; direct APIs are cheaper at scale.
- Wallet: double-entry ledger (already built for coins, section 6.6), daily reconciliation against provider statements, idempotent payment callbacks, manual review queue for large withdrawals.

### 10.6 Compliance building blocks

- KYC: national ID number and selfie, verified against NIRA through a provider.
- Age gate 25+.
- Responsible gaming: deposit limits, loss limits, session reminders, self-exclusion, cool-off.
- AML: transaction monitoring, reporting to the Financial Intelligence Authority where required.
- Data protection: register with the Personal Data Protection Office under the Data Protection and Privacy Act 2019 (applies from the free phase, since we hold phone numbers).
- An ISO 27001-aligned information security baseline will make NITA-U certification and partner due diligence much easier.

### 10.7 Money game design

- Launch money play with **1v1 only**. 4-player and 2v2 invite collusion (two friends ganging up on a stranger).
- No bots, ever, in money games, and no bot fallback in money queues.
- Friends cannot be matched against each other in money queues (reduces chip dumping).
- Stakes: tables at UGX 1,000, 2,000, 5,000, 10,000, 20,000, 50,000. Rake 10 to 15%, possibly tiered (higher percent at low stakes).

### 10.8 Kenya and Rwanda

Each country has its own regulator and tax regime. Treat expansion as a new licence project per country.

---

## 11. Trust, fairness and anti-cheat

- **Server-authoritative:** the client never rolls dice and never decides a move's result.
- **Provably fair dice:** at match start the server publishes a hash of a secret seed; each roll is derived from the seed, a client seed and the roll number; at match end the seed is revealed so anyone can verify every roll. A "Verify this game" button on the result screen.
- **Full move log** per match for dispute resolution.
- **Anti-collusion signals:** same device, same IP, same MoMo number, repeated pairings, soft play (avoiding obvious captures).
- **Rate limits** on OTP, room creation and matchmaking.
- **Bots are labelled** as bots in free games. Never disguise a bot as a human.

---

## 12. Metrics

| Metric | MVP target |
|---|---|
| Crash-free sessions | 99%+ |
| Game completion rate (started games that finish) | 80%+ |
| Reconnect success after drop | 90%+ |
| D1 / D7 retention | 35% / 15% |
| Games per daily active user | 3+ |
| Invite link to install conversion | Track from day 1 |
| Data per game | under 200 KB |
| Tutorial completion | 70%+ |

---

## 13. Engineering workflow

- **Branches:** `main` is always releasable. Work on `feat/...`, `fix/...`, merge by PR with at least one review (when both devs are active) or a self-review checklist.
- **CI (GitHub Actions):** `dart format --set-exit-if-changed`, `flutter analyze`, `flutter test`, `dart test` for the engine and server.
- **Definition of done:** tests written, works on a low-end Android device, strings localised, README updated if behaviour changed.
- **Rules changes:** update section 2 first, then code, then tests. Never the other way round.
- **Secrets:** never in the repo. `.env` files locally, secret manager in CI and production.
- **Decisions:** record significant choices as short ADRs in `docs/adr/`.

### Run the app today

```
flutter pub get
flutter run            # pick an Android device or emulator
flutter test
flutter build apk
```

---

## 14. Open questions

Decisions needed from the product owner, roughly in order of urgency. All must be closed by the end of M0.

1. Final brand name and domain (drives the Android package id, which is permanent).
2. Three double 6s in a row: forfeit or not?
3. Must both dice be used when possible? Which die is used if only one can be?
4. Combined moves: must each intermediate step be legal?
5. Own pieces and own blocks: can they only join exactly, or pass after landing?
6. Block moving on a double: moves one die's value or the sum?
7. Counting sixes for 3- and 4-piece block captures.
8. Free-for-all: play on for 2nd and 3rd, or end at the first finisher?
9. 2v2: win condition, joint blocks, rolling for partner after finishing.
10. Can the second die move the piece just released?
11. Who writes and reviews Luganda strings?
12. Play developer account: personal or organisation (affects the 14-day test rule)?
13. Who owns the legal opinion and licensed-partner conversations for the money phase, and by when?

---

## 15. Glossary

| Term | Meaning |
|---|---|
| Block | 2+ pieces of one colour on one square; acts as a wall |
| Release | Moving a piece from home onto its start square with a 6 |
| Home column | The 5 coloured squares leading to the finish |
| Finish | The centre; a piece there is done |
| Rake | The platform's percentage of each money pot |
| GGR | Gross gaming revenue: stakes minus winnings paid, i.e. our rake |
| Authoritative server | The server decides dice and moves; clients only display |
| Provably fair | Dice outcomes players can verify after the game |
| NLGRB | National Lotteries and Gaming Regulatory Board, Uganda's gaming regulator |
| KYC | Know your customer: identity and age verification |

---

## 16. Sources

- [Uganda Gambling Laws and Market Outlook 2026 (Altenar)](https://altenar.com/blog/gambling-laws-and-regulations-in-uganda-licensing-compliance-and-market-reality/)
- [Uganda's Gambling Sector in 2025: Legal and Regulatory Guide (PML Daily)](https://pmldaily.com/sports/2025/10/ugandas-gambling-sector-in-2025-a-definitive-legal-and-regulatory-guide-for-operators.html)
- [Uganda approves harmonised 30% tax rate, 15% on winnings (iGaming Business)](https://igamingbusiness.com/finance/tax/uganda-approves-harmonised-tax-betting-gaming/)
- [Strict new rules as Uganda gambling board begins 2026 licence renewals (iGamingToday)](https://www.igamingtoday.com/strict-new-rules-announced-as-uganda-gambling-board-begins-2026-license-renewals/)
- [NLGRB licensing process](https://lgrb.go.ug/licensing-process/)
- [Lotteries and Gaming Act, 2016 (ULII)](https://ulii.org/akn/ug/act/2016/7/eng@2023-12-31)
- [Google Play: Real-Money Gambling, Games, and Contests policy](https://support.google.com/googleplay/android-developer/answer/9877032)
- [MTN MoMo developer API](https://momo.mtn.com/api/)
- [Uganda payment gateways: mobile money and cards (Boldrails)](https://boldrails.com/payments/uganda)
- [Real-money Ludo in Nigeria (Carry1st)](https://www.carry1st.com/blog/can-you-earn-money-playing-ludo-online-in-nigeria-in-2025) and [MPL Nigeria](https://www.mpl.ng/): comparable real-money Ludo models
- [Colyseus](https://colyseus.io/) and Nakama: backends considered in section 6.3

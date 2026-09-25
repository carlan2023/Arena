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

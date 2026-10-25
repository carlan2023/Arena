import 'dart:async';

import 'package:arena/app/app.dart';
import 'package:arena/online/auth.dart';
import 'package:arena_protocol/arena_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../online/fakes.dart';

class _App {
  _App(this.tester);

  final WidgetTester tester;
  final connector = FakeConnector();
  final api = FakeApi();
  final links = StreamController<Uri>.broadcast();

  Future<void> start({Session? session = session}) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...onlineOverrides(connector, api: api, session: session),
          incomingLinksProvider.overrideWithValue(links.stream),
        ],
        child: const ArenaApp(),
      ),
    );
    await _settle();
  }

  Future<void> stop() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await links.close();
  }

  Future<void> _settle() async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> openWallet() async {
    await tester.scrollUntilVisible(
      find.byKey(const Key('wallet')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('wallet')));
    await _settle();
  }
}

void main() {
  testWidgets('a phone user sets a date of birth and deposits', (tester) async {
    final app = _App(tester);
    app.api.user = me;
    await app.start();
    await app.openWallet();
    expect(find.byKey(const Key('date-of-birth')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('date-of-birth')),
      '1990-01-01',
    );
    await tester.tap(find.byKey(const Key('save-dob')));
    await app._settle();
    expect(find.byKey(const Key('wallet-balance')), findsOneWidget);
    expect(find.text('0 UGX'), findsWidgets);
    expect(find.byKey(const Key('session-time')), findsOneWidget);
    expect(find.text('Today 0 UGX'), findsOneWidget);
    expect(find.textContaining('No real money'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('deposit-amount')), '5000');
    final phone = tester.widget<TextField>(
      find.byKey(const Key('deposit-phone')),
    );
    expect(phone.controller!.text, '256772000001');
    await tester.tap(find.byKey(const Key('deposit')));
    await app._settle();
    expect(find.text('5,000 UGX'), findsWidgets);
    expect(find.text('Today 5,000 UGX'), findsOneWidget);
    expect(find.text('deposit'), findsOneWidget);
    expect(app.api.calls, contains('dob 1990-01-01'));
    expect(app.api.calls, contains('deposit 5000 256772000001 fake'));
    expect(app.api.calls, contains('confirm pay-1'));
    await app.stop();
  });

  testWidgets('under 25 the wallet stays closed', (tester) async {
    final app = _App(tester);
    app.api.user = me;
    await app.start();
    await app.openWallet();
    await tester.enterText(
      find.byKey(const Key('date-of-birth')),
      '2015-01-01',
    );
    await tester.tap(find.byKey(const Key('save-dob')));
    await app._settle();
    expect(find.byKey(const Key('age-blocked')), findsOneWidget);
    expect(find.byKey(const Key('deposit')), findsNothing);
    await app.stop();
  });

  testWidgets('a guest is sent to phone login', (tester) async {
    final app = _App(tester);
    await app.start(
      session: const Session(
        token: 'guest-tok',
        user: UserView(id: 'g1', phone: '', displayName: 'Player 7f3a'),
      ),
    );
    expect(find.byKey(const Key('wallet')), findsNothing);
    expect(find.byKey(const Key('sign-in')), findsOneWidget);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).push('/wallet');
    await app._settle();
    expect(find.byKey(const Key('wallet-login')), findsOneWidget);
    await tester.tap(find.byKey(const Key('wallet-login')));
    await app._settle();
    expect(find.byKey(const Key('phone')), findsOneWidget);
    await app.stop();
  });

  testWidgets('self exclusion closes the deposit button', (tester) async {
    final app = _App(tester);
    app.api.user = me;
    app.api.limitsView = const LimitsView(
      daily: 1000000,
      weekly: 7000000,
      monthly: 30000000,
      permanent: true,
    );
    await app.start();
    await app.openWallet();
    await tester.enterText(
      find.byKey(const Key('date-of-birth')),
      '1990-01-01',
    );
    await tester.tap(find.byKey(const Key('save-dob')));
    await app._settle();
    expect(find.byKey(const Key('excluded')), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('deposit')),
    );
    expect(button.onPressed, isNull);
    await app.stop();
  });
}

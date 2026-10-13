import 'package:arena/game/bots.dart';
import 'package:arena/ui/local_setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [320.0, 360.0]) {
    testWidgets('setup fits a ${width.toInt()} px wide phone in every mode', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(home: LocalSetupScreen(onStart: (_) {})),
      );
      for (final mode in ['1v1', 'All', '2v2']) {
        await tester.tap(find.text(mode));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: mode);
        for (final dropdown
            in find.byType(DropdownButton<SeatKind?>).evaluate()) {
          final box = tester.getRect(find.byWidget(dropdown.widget));
          expect(box.right, lessThanOrEqualTo(width), reason: mode);
        }
        // The colour name stays on one line instead of being squeezed.
        expect(tester.getSize(find.text('Red')).height, lessThan(30));
      }
    });
  }
}

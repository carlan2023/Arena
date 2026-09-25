import 'dart:io';

import 'package:arena/widgets/dice_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every face has an asset file that exists (B1)', () {
    for (var value = 1; value <= 6; value++) {
      final path = DiceWidget.assetFor(value);
      expect(path, 'assets/dice$value.png');
      expect(File(path).existsSync(), isTrue, reason: path);
    }
  });

  test('values outside 1 to 6 are rejected', () {
    expect(() => DiceWidget.assetFor(0), throwsRangeError);
    expect(() => DiceWidget.assetFor(7), throwsRangeError);
  });

  testWidgets('shows the face 1 image and rolls on tap', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: DiceWidget())),
    );
    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as AssetImage).assetName, 'assets/dice1.png');

    await tester.tap(find.byType(DiceWidget));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    final rolled = tester.widget<Image>(find.byType(Image));
    expect(
      (rolled.image as AssetImage).assetName,
      matches(RegExp(r'^assets/dice[1-6]\.png$')),
    );
  });
}

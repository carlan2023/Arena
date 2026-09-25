import 'package:arena/widgets/ludo_board.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Color cell(int row, int col) => LudoBoard.cellColor(row, col);

void main() {
  test('inner square of each yard is white (B2)', () {
    for (final (rows, cols) in [
      ((1, 4), (1, 4)),
      ((1, 4), (10, 13)),
      ((10, 13), (1, 4)),
      ((10, 13), (10, 13)),
    ]) {
      for (var r = rows.$1; r <= rows.$2; r++) {
        for (var c = cols.$1; c <= cols.$2; c++) {
          expect(cell(r, c), Colors.white, reason: '($r, $c)');
        }
      }
    }
  });

  test('yard borders keep their colour', () {
    expect(cell(0, 0), Colors.red.shade300);
    expect(cell(5, 5), Colors.red.shade300);
    expect(cell(0, 14), Colors.green.shade300);
    expect(cell(14, 14), Colors.yellow.shade300);
    expect(cell(14, 0), Colors.blue.shade300);
  });

  test('home columns match their yard and the engine layout (B3)', () {
    // Red: left arm, green: top, yellow: right, blue: bottom.
    for (var i = 1; i <= 5; i++) {
      expect(cell(7, i), Colors.red.shade200, reason: 'red $i');
      expect(cell(i, 7), Colors.green.shade200, reason: 'green $i');
      expect(cell(7, 14 - i), Colors.yellow.shade200, reason: 'yellow $i');
      expect(cell(14 - i, 7), Colors.blue.shade200, reason: 'blue $i');
    }
    // Centre edges point at the matching arm.
    expect(cell(7, 6), Colors.red.shade300);
    expect(cell(6, 7), Colors.green.shade300);
    expect(cell(7, 8), Colors.yellow.shade300);
    expect(cell(8, 7), Colors.blue.shade300);
  });

  test('outer track squares are white', () {
    expect(cell(6, 0), Colors.white);
    expect(cell(7, 0), Colors.white);
    expect(cell(0, 7), Colors.white);
    expect(cell(14, 7), Colors.white);
    expect(cell(6, 1), Colors.white);
  });

  testWidgets('builds the grid', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: LudoBoard())),
    );
    expect(find.byType(GridView), findsOneWidget);
  });
}

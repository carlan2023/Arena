import 'package:flutter/material.dart';

class LudoBoard extends StatelessWidget {
  const LudoBoard({super.key});

  /// Colour of one cell on the 15 by 15 grid, (row, col) from the top left.
  /// Layout follows docs/contracts/engine_api.md: red yard top left with the
  /// left arm, then clockwise green (top), yellow (right), blue (bottom).
  @visibleForTesting
  static Color cellColor(int row, int col) {
    // Inner white square of each yard, checked before the yard colour.
    final innerRow = (row >= 1 && row <= 4) || (row >= 10 && row <= 13);
    final innerCol = (col >= 1 && col <= 4) || (col >= 10 && col <= 13);
    if (innerRow && innerCol) return Colors.white;

    // Yards (6 by 6 corners).
    if (row <= 5 && col <= 5) return Colors.red.shade300;
    if (row <= 5 && col >= 9) return Colors.green.shade300;
    if (row >= 9 && col >= 9) return Colors.yellow.shade300;
    if (row >= 9 && col <= 5) return Colors.blue.shade300;

    // Centre 3 by 3. Each edge cell takes the colour of the arm it touches.
    if (row >= 6 && row <= 8 && col >= 6 && col <= 8) {
      if (row == 7 && col == 6) return Colors.red.shade300;
      if (row == 6 && col == 7) return Colors.green.shade300;
      if (row == 7 && col == 8) return Colors.yellow.shade300;
      if (row == 8 && col == 7) return Colors.blue.shade300;
      return Colors.white;
    }

    // Home columns, 5 squares each, leading to the centre.
    if (row == 7 && col >= 1 && col <= 5) return Colors.red.shade200;
    if (col == 7 && row >= 1 && row <= 5) return Colors.green.shade200;
    if (row == 7 && col >= 9 && col <= 13) return Colors.yellow.shade200;
    if (col == 7 && row >= 9 && row <= 13) return Colors.blue.shade200;

    // Everything else is a plain track square.
    return Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    // Use the parent's constraints to choose the largest square that fits.
    return LayoutBuilder(
      builder: (context, constraints) {
        // Take 95% of the smaller dimension so there's some breathing room
        final maxSide = constraints.maxWidth < constraints.maxHeight
            ? constraints.maxWidth
            : constraints.maxHeight;
        final boardSize = (maxSide * 0.95).clamp(200.0, maxSide);

        return Center(
          child: SizedBox(
            width: boardSize,
            height: boardSize,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.black87, width: 2),
              ),
              child: GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 15,
                  childAspectRatio: 1.0,
                ),
                itemCount: 15 * 15,
                itemBuilder: (context, index) {
                  final row = index ~/ 15;
                  final col = index % 15;
                  final color = cellColor(row, col);

                  return Container(
                    decoration: BoxDecoration(
                      color: color,
                      border: Border.all(color: Colors.black12),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

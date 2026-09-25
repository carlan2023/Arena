import 'package:flutter/material.dart';

class LudoBoard extends StatelessWidget {
  const LudoBoard({super.key});

  Color? _cellColor(int row, int col) {
    // Corner homes (6x6)
    if (row >= 0 && row <= 5 && col >= 0 && col <= 5) {
      // top-left: red
      return Colors.red.shade300;
    }
    if (row >= 0 && row <= 5 && col >= 9 && col <= 14) {
      // top-right: green
      return Colors.green.shade300;
    }
    if (row >= 9 && row <= 14 && col >= 0 && col <= 5) {
      // bottom-left: blue
      return Colors.blue.shade300;
    }
    if (row >= 9 && row <= 14 && col >= 9 && col <= 14) {
      // bottom-right: yellow
      return Colors.yellow.shade300;
    }

    // Home-inner white squares inside each corner (make an inner 4x4 white area)
    if (row >= 1 && row <= 4 && col >= 1 && col <= 4) {
      return Colors.white;
    }
    if (row >= 1 && row <= 4 && col >= 10 && col <= 13) {
      return Colors.white;
    }
    if (row >= 10 && row <= 13 && col >= 1 && col <= 4) {
      return Colors.white;
    }
    if (row >= 10 && row <= 13 && col >= 10 && col <= 13) {
      return Colors.white;
    }

    // Center 3x3 region (rows 6..8, cols 6..8) - split into four quadrant colors
    if (row >= 6 && row <= 8 && col >= 6 && col <= 8) {
      if (row < 7 && col < 7) {
        return Colors.red.shade300; // top-left of center
      }
      if (row < 7 && col > 7) {
        return Colors.green.shade300; // top-right of center
      }
      if (row > 7 && col < 7) {
        return Colors.blue.shade300; // bottom-left of center
      }
      if (row > 7 && col > 7) {
        return Colors.yellow.shade300; // bottom-right of center
      }
      // center cell remains white
      return Colors.white;
    }

    // Path arms that lead to the center (length 6)
    // Red (top): same column as center (7), rows 1..6
    if (col == 7 && row >= 1 && row <= 6) {
      return Colors.red.shade200;
    }
    // Green (right): same row as center (7), cols 8..13
    if (row == 7 && col >= 8 && col <= 13) {
      return Colors.green.shade200;
    }
    // Yellow (down): col 7, rows 8..13
    if (col == 7 && row >= 8 && row <= 13) {
      return Colors.yellow.shade200;
    }
    // Blue (left): row 7, cols 1..6
    if (row == 7 && col >= 1 && col <= 6) {
      return Colors.blue.shade200;
    }

    // All other squares are plain white path tiles
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
                  final color = _cellColor(row, col);

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

import 'package:flutter/material.dart';
import '../widgets/ludo_board.dart';
import '../widgets/dice_widget.dart';

class BoardScreen extends StatelessWidget {
  const BoardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.green.shade50,
      appBar: AppBar(title: const Text("Arena Ludo Board")),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // On wide screens place the dice to the right, on narrow screens place below
          final bool wide = constraints.maxWidth > 800;

          if (wide) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 16.0,
                  horizontal: 8.0,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Board takes available width but limited to a sensible max via its own LayoutBuilder
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: 900),
                          child: const LudoBoard(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 24),
                    // Side panel for dice and controls
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: const [DiceWidget(), SizedBox(height: 16)],
                    ),
                  ],
                ),
              ),
            );
          }

          // Narrow layout: board above, dice below
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Expanded(child: LudoBoard()),
              SizedBox(height: 20),
              DiceWidget(),
              SizedBox(height: 40),
            ],
          );
        },
      ),
    );
  }
}

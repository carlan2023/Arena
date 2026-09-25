import 'dart:math';
import 'package:flutter/material.dart';

class DiceWidget extends StatefulWidget {
  const DiceWidget({super.key});

  /// Asset path of the image for a die showing [value] (1 to 6).
  static String assetFor(int value) {
    if (value < 1 || value > 6) {
      throw RangeError.range(value, 1, 6, 'value');
    }
    return 'assets/dice$value.png';
  }

  @override
  State<DiceWidget> createState() => _DiceWidgetState();
}

class _DiceWidgetState extends State<DiceWidget>
    with SingleTickerProviderStateMixin {
  int diceNumber = 1;
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
  }

  void rollDice() {
    _controller.forward(from: 0);
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      setState(() {
        diceNumber = Random().nextInt(6) + 1;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final assetName = DiceWidget.assetFor(diceNumber);

    return GestureDetector(
      onTap: rollDice,
      child: RotationTransition(
        turns: Tween(
          begin: 0.0,
          end: 1.0,
        ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut)),
        child: Image.asset(assetName, width: 80, height: 80),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

import 'dart:math';
import 'package:flutter/material.dart';

class DiceWidget extends StatefulWidget {
  const DiceWidget({super.key});

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
      setState(() {
        diceNumber = Random().nextInt(6) + 1;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    String assetName;
    // Use the project's dice asset naming if present, otherwise fall back to numeric names
    switch (diceNumber) {
      case 1:
        assetName = 'assets/dice1.png';
        break;
      case 2:
        assetName = 'assets/dice2.png';
        break;
      case 3:
        assetName = 'assets/dice3.png';
        break;
      case 4:
        assetName = 'assets/dice4.png';
        break;
      case 5:
        assetName = 'assets/dice5.png';
        break;
      case 6:
        assetName = 'assets/dice6.png';
        break;
      default:
        assetName = 'assets/dice6.png';
    }

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

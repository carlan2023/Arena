import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ui/local_game_screen.dart';
import '../ui/local_setup_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Arena')),
      body: Center(
        child: FilledButton(
          key: const Key('pass-and-play'),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => LocalSetupScreen(
                onStart: (config) => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        ProviderScope(child: LocalGameScreen(config: config)),
                  ),
                ),
              ),
            ),
          ),
          child: const Text('Pass and play'),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ludo_engine/ludo_engine.dart';

import '../game/local_game.dart';
import 'game_table.dart';

/// Pass and play: everyone shares one phone, bots fill any seats.
class LocalGameScreen extends ConsumerWidget {
  const LocalGameScreen({super.key, required this.config});

  final LocalGameConfig config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = localGameProvider(config);
    final view = ref.watch(provider);
    final over = view.state.phase == TurnPhase.gameOver;
    return Scaffold(
      appBar: AppBar(title: const Text('Pass and play')),
      body: SafeArea(
        child: Stack(
          children: [
            GameTable(view: view, actions: ref.read(provider.notifier)),
            if (over)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black54,
                  child: Center(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              view.message ?? 'Game over',
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 16),
                            FilledButton(
                              key: const Key('play-again'),
                              onPressed: () => ref.invalidate(provider),
                              child: const Text('Play again'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

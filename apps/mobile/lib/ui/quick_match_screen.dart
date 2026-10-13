import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ludo_engine/ludo_engine.dart';

import '../online/quick_match.dart';

/// Searching for players: who has been found, how long we waited, when bots
/// fill the empty seats, and a cancel button (m3.md section 6).
class QuickMatchScreen extends ConsumerStatefulWidget {
  const QuickMatchScreen({super.key, required this.table});

  final QuickMatchTable table;

  @override
  ConsumerState<QuickMatchScreen> createState() => _QuickMatchScreenState();
}

class _QuickMatchScreenState extends ConsumerState<QuickMatchScreen> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _cancel() {
    ref.read(quickMatchProvider(widget.table).notifier).cancel();
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(quickMatchProvider(widget.table), (_, next) {
      final code = next.roomCode;
      if (code != null) context.pushReplacement('/room/$code');
    });
    final view = ref.watch(quickMatchProvider(widget.table));
    final text = Theme.of(context).textTheme;
    final now = DateTime.now();
    final waited = view.waitedSince == null
        ? 0
        : now.difference(view.waitedSince!).inSeconds;
    final fillIn = view.botFillAt?.difference(now).inSeconds;
    final title = widget.table.mode == GameMode.oneVsOne
        ? 'Quick match, 1 v 1'
        : 'Quick match, 4 players';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              if (view.searching) ...[
                const SizedBox(
                  width: 64,
                  height: 64,
                  child: CircularProgressIndicator(),
                ),
                const SizedBox(height: 24),
                Text(
                  view.connected
                      ? 'Looking for players'
                      : 'Connecting to the server',
                  style: text.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  key: const Key('players-found'),
                  '${view.playersFound} of ${view.playersNeeded} players found',
                  style: text.bodyLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  key: const Key('waited'),
                  'Waiting ${_clock(waited)}',
                  style: text.bodyMedium,
                ),
                if (fillIn != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    key: const Key('bot-fill'),
                    fillIn > 0
                        ? 'Bots take the empty seats in ${fillIn}s'
                        : 'Bots are taking the empty seats',
                    style: text.bodyMedium,
                  ),
                ],
              ] else ...[
                Icon(
                  view.error == null ? Icons.check_circle : Icons.info_outline,
                  size: 64,
                ),
                const SizedBox(height: 16),
                Text(
                  view.error ?? 'Found a game',
                  style: text.titleMedium,
                  textAlign: TextAlign.center,
                ),
              ],
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: view.searching
                    ? OutlinedButton(
                        key: const Key('cancel-search'),
                        onPressed: _cancel,
                        child: const Text('Cancel'),
                      )
                    : FilledButton(
                        key: const Key('back-home'),
                        onPressed: () => context.go('/'),
                        child: const Text('Back to home'),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _clock(int seconds) {
    final m = seconds ~/ 60;
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

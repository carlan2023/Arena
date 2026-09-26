import 'package:arena_protocol/arena_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ludo_engine/ludo_engine.dart';
import 'package:share_plus/share_plus.dart';

import '../board/board_palette.dart';
import '../game/local_game.dart' show colorName;
import '../online/room_controller.dart';
import 'game_table.dart';

/// Sends the invite through the phone's share sheet (WhatsApp and others).
typedef ShareText = Future<void> Function(String text);

final shareTextProvider = Provider<ShareText>(
  (ref) =>
      (text) => SharePlus.instance.share(ShareParams(text: text)),
);

/// Quick chat: ready made phrases only, no free typing (README section 7).
/// Luganda phrases come once native speakers have written them.
const quickChat = {
  'hello': 'Hello!',
  'nice': 'Nice move',
  'hurry': 'Your turn!',
  'gg': 'Good game',
};

/// A room from lobby to results: /room/:code.
class RoomScreen extends ConsumerStatefulWidget {
  const RoomScreen({super.key, required this.code});

  final String code;

  @override
  ConsumerState<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends ConsumerState<RoomScreen> {
  late final AppLifecycleListener _lifecycle = AppLifecycleListener(
    onResume: () => ref.read(roomProvider(widget.code).notifier).resume(),
  );

  @override
  void initState() {
    super.initState();
    _lifecycle;
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = roomProvider(widget.code);
    final view = ref.watch(provider);
    final controller = ref.read(provider.notifier);

    ref.listen(provider.select((v) => v.emote), (_, emote) {
      if (emote == null) return;
      final (seat, id) = emote;
      final name = _nameOfSeat(ref.read(provider).room, seat);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('$name: ${quickChat[id] ?? id}'),
            duration: const Duration(seconds: 2),
          ),
        );
    });

    final Widget body;
    if (view.fatal != null) {
      body = _Notice(
        text: view.fatal!,
        action: FilledButton(
          onPressed: () => context.go('/'),
          child: const Text('Home'),
        ),
      );
    } else if (view.gameOver != null) {
      body = _Results(view: view);
    } else if (view.table != null) {
      body = GameTable(
        view: view.table!,
        actions: controller,
        footer: _QuickChat(onSend: controller.sendEmote),
      );
    } else if (view.room != null) {
      body = _Lobby(view: view, controller: controller);
    } else {
      body = const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Room ${widget.code}'),
        leading: IconButton(
          tooltip: 'Leave',
          icon: const Icon(Icons.close),
          onPressed: () async {
            final playing = view.table != null && view.gameOver == null;
            if (playing && !await _confirmLeave(context)) return;
            controller.leave();
            if (context.mounted) context.go('/');
          },
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (view.connection == Connection.reconnecting &&
                view.fatal == null)
              const MaterialBanner(
                key: Key('reconnecting'),
                content: Text('Connection lost. Reconnecting...'),
                leading: Icon(Icons.wifi_off),
                actions: [SizedBox.shrink()],
              ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }

  static Future<bool> _confirmLeave(BuildContext context) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Leave the game?'),
          content: const Text('Leaving now counts as a forfeit.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Stay'),
            ),
            FilledButton(
              key: const Key('confirm-leave'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Leave'),
            ),
          ],
        ),
      ) ??
      false;
}

String _nameOfSeat(RoomView? room, int seat) {
  for (final p in room?.players ?? const <PlayerView>[]) {
    if (p.seat == seat) return p.displayName;
  }
  return 'Seat ${seat + 1}';
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.action});

  final String text;
  final Widget action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          action,
        ],
      ),
    ),
  );
}

class _Lobby extends ConsumerWidget {
  const _Lobby({required this.view, required this.controller});

  final RoomScreenView view;
  final RoomController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = view.room!;
    final canStart = view.isOwner && room.players.length >= 2;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Room code', style: Theme.of(context).textTheme.labelLarge),
        SelectableText(
          room.code,
          key: const Key('lobby-code'),
          style: Theme.of(
            context,
          ).textTheme.displaySmall?.copyWith(letterSpacing: 6),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          key: const Key('share'),
          icon: const Icon(Icons.share),
          label: const Text('Invite on WhatsApp'),
          onPressed: () => ref.read(shareTextProvider)(
            'Play Ludo with me on Arena! Room ${room.code}: ${room.link}',
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Players ${room.players.length} of ${room.seats}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        for (final p in room.players)
          ListTile(
            leading: CircleAvatar(
              backgroundColor: p.color == null
                  ? Colors.grey
                  : BoardPalette.standard.player(p.color!.index),
              child: Icon(p.isBot ? Icons.smart_toy : Icons.person),
            ),
            title: Text(
              p.seat == view.you?.seat
                  ? '${p.displayName} (you)'
                  : p.displayName,
            ),
            subtitle: Text(
              [
                if (p.userId == room.ownerUserId) 'Host',
                if (!p.connected) 'Offline',
              ].join(' · '),
            ),
          ),
        const SizedBox(height: 24),
        if (view.isOwner)
          FilledButton(
            key: const Key('start-game'),
            onPressed: canStart ? controller.startGame : null,
            child: Text(canStart ? 'Start game' : 'Waiting for players'),
          )
        else
          const Text(
            'Waiting for the host to start. The game also starts when '
            'every seat is full.',
            textAlign: TextAlign.center,
          ),
      ],
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({required this.view});

  final RoomScreenView view;

  @override
  Widget build(BuildContext context) {
    final over = view.gameOver!;
    final me = view.you?.color;
    final won = me != null && over.winners.contains(me);
    final names = <PlayerColor, String>{
      for (final p in view.room?.players ?? const <PlayerView>[])
        if (p.color case final c?) c: p.displayName,
    };
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          won ? 'You won!' : 'Game over',
          key: const Key('result-title'),
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 16),
        for (var i = 0; i < over.ranking.length; i++)
          ListTile(
            leading: CircleAvatar(
              backgroundColor: BoardPalette.standard.player(
                over.ranking[i].index,
              ),
              child: Text('${i + 1}'),
            ),
            title: Text(names[over.ranking[i]] ?? colorName(over.ranking[i])),
            trailing: over.winners.contains(over.ranking[i])
                ? const Icon(Icons.emoji_events)
                : null,
          ),
        const SizedBox(height: 24),
        FilledButton(
          key: const Key('results-home'),
          onPressed: () => context.go('/'),
          child: const Text('Home'),
        ),
      ],
    );
  }
}

class _QuickChat extends StatelessWidget {
  const _QuickChat({required this.onSend});

  final ValueChanged<String> onSend;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Row(
      children: [
        for (final e in quickChat.entries)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ActionChip(
              key: Key('emote-${e.key}'),
              label: Text(e.value),
              onPressed: () => onSend(e.key),
            ),
          ),
      ],
    ),
  );
}

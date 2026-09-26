import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ludo_engine/ludo_engine.dart';

import '../online/api.dart';
import '../online/auth.dart';
import '../online/config.dart';

/// Play with friends, join by code, or pass and play.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _busy = false;

  Future<void> _createRoom() async {
    final choice = await showModalBottomSheet<(GameMode, int)>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (label, mode, seats) in const [
              ('1 v 1', GameMode.oneVsOne, 2),
              ('Free for all, 3 players', GameMode.freeForAll, 3),
              ('Free for all, 4 players', GameMode.freeForAll, 4),
              ('2 v 2 teams', GameMode.teams, 4),
            ])
              ListTile(
                title: Text(label),
                onTap: () => Navigator.pop(context, (mode, seats)),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    final session = ref.read(authProvider).value;
    if (session == null) return;
    setState(() => _busy = true);
    try {
      final room = await ref
          .read(arenaApiProvider)
          .createRoom(session.token, mode: choice.$1, seats: choice.$2);
      if (mounted) context.push('/room/${room.code}');
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not create a room. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _joinByCode() async {
    final code = await showDialog<String>(
      context: context,
      builder: (context) => const _JoinDialog(),
    );
    if (code == null || !mounted) return;
    if (!isRoomCode(code)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Room codes have 6 letters and digits')),
      );
      return;
    }
    context.push('/room/$code');
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authProvider).value;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Arena'),
        actions: [
          if (session != null)
            IconButton(
              tooltip: 'Log out',
              icon: const Icon(Icons.logout),
              onPressed: () => ref.read(authProvider.notifier).logout(),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (session != null)
              Text(
                'Hello, ${session.user.displayName}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const Key('play-friends'),
              onPressed: _busy || session == null ? null : _createRoom,
              icon: const Icon(Icons.group_add),
              label: const Text('Play with friends'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('join-code'),
              onPressed: session == null ? null : _joinByCode,
              icon: const Icon(Icons.login),
              label: const Text('Join with a code'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('pass-and-play'),
              onPressed: () => context.push('/local'),
              icon: const Icon(Icons.phone_android),
              label: const Text('Pass and play'),
            ),
          ],
        ),
      ),
    );
  }
}

class _JoinDialog extends StatefulWidget {
  const _JoinDialog();

  @override
  State<_JoinDialog> createState() => _JoinDialogState();
}

class _JoinDialogState extends State<_JoinDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Join with a code'),
    content: TextField(
      key: const Key('room-code'),
      controller: _controller,
      autofocus: true,
      textCapitalization: TextCapitalization.characters,
      maxLength: 6,
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const Key('join'),
        onPressed: () =>
            Navigator.pop(context, _controller.text.trim().toUpperCase()),
        child: const Text('Join'),
      ),
    ],
  );
}

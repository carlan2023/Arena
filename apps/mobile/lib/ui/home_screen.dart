import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ludo_engine/ludo_engine.dart';

import '../online/api.dart';
import '../online/auth.dart';
import '../online/coins.dart';
import '../online/config.dart';
import 'avatar.dart';

/// Play with friends, join by code, or pass and play.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _busy = false;

  Future<void> _quick(GameMode mode) async {
    final entry = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (label, amount) in const [
              ('Free', 0),
              ('50 coins', 50),
              ('200 coins', 200),
              ('1000 coins', 1000),
            ])
              ListTile(
                key: Key('table-$amount'),
                title: Text(label),
                onTap: () => Navigator.pop(context, amount),
              ),
          ],
        ),
      ),
    );
    if (entry == null || !mounted) return;
    final path = entry == 0
        ? '/quick/${mode.name}'
        : '/quick/${mode.name}/$entry';
    context.push(path);
  }

  Future<void> _createRoom() async {
    final choice = await showModalBottomSheet<(GameMode, int, int)>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final (label, mode, seats, entry) in const [
              ('1 v 1', GameMode.oneVsOne, 2, 0),
              ('Free for all, 3 players', GameMode.freeForAll, 3, 0),
              ('Free for all, 4 players', GameMode.freeForAll, 4, 0),
              ('2 v 2 teams', GameMode.teams, 4, 0),
              ('1 v 1, 50 coins', GameMode.oneVsOne, 2, 50),
              ('1 v 1, 200 coins', GameMode.oneVsOne, 2, 200),
              ('1 v 1, 1000 coins', GameMode.oneVsOne, 2, 1000),
              ('3 players, 50 coins', GameMode.freeForAll, 3, 50),
              ('3 players, 200 coins', GameMode.freeForAll, 3, 200),
              ('3 players, 1000 coins', GameMode.freeForAll, 3, 1000),
              ('4 players, 50 coins', GameMode.freeForAll, 4, 50),
              ('4 players, 200 coins', GameMode.freeForAll, 4, 200),
              ('4 players, 1000 coins', GameMode.freeForAll, 4, 1000),
            ])
              ListTile(
                title: Text(label),
                onTap: () => Navigator.pop(context, (mode, seats, entry)),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    setState(() => _busy = true);
    try {
      // No sign up for free play: a guest session is made if needed (D33).
      final session = await ref.read(authProvider.notifier).ensureSession();
      final room = await ref
          .read(arenaApiProvider)
          .createRoom(
            session.token,
            mode: choice.$1,
            seats: choice.$2,
            entry: choice.$3,
          );
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
    final verified = session != null && !session.isGuest;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Arena'),
        actions: [
          IconButton(
            key: const Key('profile'),
            tooltip: 'Profile',
            onPressed: () => context.push('/profile'),
            icon: session == null
                ? const Icon(Icons.account_circle)
                : ArenaAvatar(avatar: session.user.avatar, radius: 14),
          ),
          if (verified)
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
            Text(
              session == null
                  ? 'Ludo the way we play it'
                  : 'Hello, ${session.user.displayName}',
              style: text.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              verified
                  ? 'Free and paid tables are open to you.'
                  : 'Free games need no sign up. Just play.',
              style: text.bodyMedium,
            ),
            if (session != null) ...[
              const SizedBox(height: 16),
              const _CoinsCard(),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    key: const Key('quick-1v1'),
                    onPressed: () => _quick(GameMode.oneVsOne),
                    icon: const Icon(Icons.bolt),
                    label: const Text('Quick 1 v 1'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    key: const Key('quick-4'),
                    onPressed: () => _quick(GameMode.freeForAll),
                    icon: const Icon(Icons.groups),
                    label: const Text('Quick 4 players'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              key: const Key('play-friends'),
              onPressed: _busy ? null : _createRoom,
              icon: const Icon(Icons.group_add),
              label: const Text('Play with friends'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('join-code'),
              onPressed: _joinByCode,
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
            if (verified) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('wallet'),
                onPressed: () => context.push('/wallet'),
                icon: const Icon(Icons.account_balance_wallet_outlined),
                label: const Text('Wallet'),
              ),
            ],
            if (!verified) ...[
              const SizedBox(height: 32),
              Card(
                child: ListTile(
                  key: const Key('sign-in'),
                  leading: const Icon(Icons.account_balance_wallet_outlined),
                  title: const Text('Play for money'),
                  subtitle: const Text(
                    'Paid tables and the wallet need your phone number.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/login'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The coin balance and the daily reward (M3.4, D36).
class _CoinsCard extends ConsumerStatefulWidget {
  const _CoinsCard();

  @override
  ConsumerState<_CoinsCard> createState() => _CoinsCardState();
}

class _CoinsCardState extends ConsumerState<_CoinsCard> {
  bool _claiming = false;

  Future<void> _claim() async {
    setState(() => _claiming = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final grant = await ref.read(coinsProvider.notifier).claimDaily();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            grant == null
                ? 'Today\'s reward was already claimed'
                : '+${grant.granted} coins. Day ${grant.streak} in a row!',
          ),
        ),
      );
    } on Object {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not claim the reward. Try again.')),
      );
    } finally {
      if (mounted) setState(() => _claiming = false);
    }
  }

  static String _wait(Duration d) {
    if (d.inHours >= 1) return '${d.inHours} h ${d.inMinutes % 60} min';
    return '${d.inMinutes.clamp(1, 59)} min';
  }

  @override
  Widget build(BuildContext context) {
    final coins = ref.watch(coinsProvider).value;
    if (coins == null) return const SizedBox.shrink();
    final daily = coins.dailyReward;
    final text = Theme.of(context).textTheme;
    return Card(
      key: const Key('coins-card'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            Icon(Icons.toll, color: Colors.amber.shade700, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${coins.balance} coins',
                    key: const Key('coins-balance'),
                    style: text.titleMedium,
                  ),
                  Text(
                    daily.available
                        ? 'Daily reward: ${daily.amount} coins'
                        : 'Next reward in '
                              '${_wait(daily.nextAt.difference(DateTime.now()))}',
                    key: const Key('daily-status'),
                    style: text.bodySmall,
                  ),
                ],
              ),
            ),
            if (daily.available)
              FilledButton(
                key: const Key('claim-daily'),
                onPressed: _claiming ? null : _claim,
                child: const Text('Claim'),
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

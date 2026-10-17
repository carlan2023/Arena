import 'package:arena_protocol/arena_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ludo_engine/ludo_engine.dart';

import '../online/api.dart';
import '../online/auth.dart';
import 'avatar.dart';

/// The player's last matches, loaded when the profile opens.
final recentMatchesProvider = FutureProvider.autoDispose<List<RecentMatchView>>(
  (ref) async {
    final session = await ref.read(authProvider.notifier).ensureSession();
    return ref.read(arenaApiProvider).recentMatches(session.token);
  },
);

/// Name, avatar and recent matches (M3.3). Opening it as a new player starts
/// a guest account, like any other online action (D33).
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _name = TextEditingController();
  bool _saving = false;
  String? _nameError;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authProvider).value?.user;
    if (user != null) _name.text = user.displayName;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save({String? name, int? avatar}) async {
    if (name != null) {
      final trimmed = name.trim();
      if (trimmed.isEmpty || trimmed.runes.length > 24) {
        setState(() => _nameError = 'Use 1 to 24 letters');
        return;
      }
      name = trimmed;
    }
    setState(() {
      _saving = true;
      _nameError = null;
    });
    try {
      await ref
          .read(authProvider.notifier)
          .setProfile(name: name, avatar: avatar);
      if (mounted && name != null) {
        FocusScope.of(context).unfocus();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Name saved')));
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authProvider, (previous, next) {
      final before = previous?.value?.user.displayName;
      final user = next.value?.user;
      if (user != null && before == null && _name.text.isEmpty) {
        _name.text = user.displayName;
      }
    });
    final user = ref.watch(authProvider).value?.user;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Center(
              child: ArenaAvatar(
                key: const Key('profile-avatar'),
                avatar: user?.avatar ?? 0,
                radius: 40,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('profile-name'),
                    controller: _name,
                    maxLength: 24,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: 'Your name',
                      errorText: _nameError,
                    ),
                    onSubmitted: (v) => _save(name: v),
                  ),
                ),
                const SizedBox(width: 12),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: FilledButton(
                    key: const Key('save-name'),
                    onPressed: _saving || user == null
                        ? null
                        : () => _save(name: _name.text),
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
            if (user != null && user.isGuest)
              Text(
                'You are playing as a guest. Your profile stays on this phone.',
                style: text.bodySmall,
              ),
            const SizedBox(height: 24),
            Text('Choose an avatar', style: text.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (var i = 0; i < avatarPresets.length; i++)
                  _AvatarChoice(
                    avatar: i,
                    selected: user?.avatar == i,
                    onTap: _saving || user == null
                        ? null
                        : () => _save(avatar: i),
                  ),
              ],
            ),
            const SizedBox(height: 32),
            Text('Recent games', style: text.titleMedium),
            const SizedBox(height: 8),
            const _RecentMatches(),
          ],
        ),
      ),
    );
  }
}

class _AvatarChoice extends StatelessWidget {
  const _AvatarChoice({
    required this.avatar,
    required this.selected,
    required this.onTap,
  });

  final int avatar;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Avatar ${avatar + 1}',
    selected: selected,
    button: true,
    child: InkWell(
      key: Key('avatar-$avatar'),
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            width: 3,
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Colors.transparent,
          ),
        ),
        child: ArenaAvatar(avatar: avatar, radius: 22),
      ),
    ),
  );
}

class _RecentMatches extends ConsumerWidget {
  const _RecentMatches();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matches = ref.watch(recentMatchesProvider);
    return matches.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => ListTile(
        key: const Key('recent-error'),
        title: const Text('Could not load your games'),
        trailing: TextButton(
          onPressed: () => ref.invalidate(recentMatchesProvider),
          child: const Text('Retry'),
        ),
      ),
      data: (list) => list.isEmpty
          ? const ListTile(
              key: Key('recent-empty'),
              title: Text('No games yet. Your finished games show here.'),
            )
          : Column(
              children: [
                for (var i = 0; i < list.length; i++)
                  _RecentTile(key: Key('recent-$i'), match: list[i]),
              ],
            ),
    );
  }
}

class _RecentTile extends StatelessWidget {
  const _RecentTile({super.key, required this.match});

  final RecentMatchView match;

  static const _places = ['1st', '2nd', '3rd', '4th'];

  @override
  Widget build(BuildContext context) {
    final m = match;
    final mode = switch (m.mode) {
      GameMode.oneVsOne => '1 v 1',
      GameMode.freeForAll => 'Free for all',
      GameMode.teams => '2 v 2',
    };
    final rank = m.rank;
    final result = m.abandoned || rank == null
        ? 'Not finished'
        : rank == 1
        ? 'Won'
        : '${_places[(rank - 1).clamp(0, 3)]} of ${m.players.length}';
    final local = m.endedAt.toLocal();
    final day =
        '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        rank == 1 ? Icons.emoji_events : Icons.casino_outlined,
        color: rank == 1 ? Colors.amber.shade700 : null,
      ),
      title: Text('$result · $mode'),
      subtitle: Text(
        [for (final p in m.players) p.displayName].join(', '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(day),
    );
  }
}

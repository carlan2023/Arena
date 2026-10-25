import 'dart:async';

import 'package:arena_protocol/arena_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../online/api.dart';
import '../online/auth.dart';

/// Balance, a test deposit, history, limits and self exclusion (M3.10, M3.11).
///
/// The age gate uses 25, the same default as MIN_AGE. The server still decides.
class WalletScreen extends ConsumerStatefulWidget {
  const WalletScreen({super.key});

  @override
  ConsumerState<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends ConsumerState<WalletScreen> {
  static const _minAge = 25;

  final _dob = TextEditingController();
  final _amount = TextEditingController();
  final _phone = TextEditingController();
  final _daily = TextEditingController();
  final _weekly = TextEditingController();
  final _monthly = TextEditingController();
  final _opened = DateTime.now();
  Timer? _ticker;

  bool _busy = false;
  bool _loading = false;
  bool _askedLoad = false;
  bool _limitsFilled = false;
  String? _formError;
  int? _balance;
  List<WalletEntryView> _history = const [];
  LimitsView? _limits;
  String _period = '1d';

  @override
  void initState() {
    super.initState();
    final phone = ref.read(authProvider).value?.user.phone ?? '';
    if (phone.startsWith('+')) _phone.text = phone.substring(1);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _dob.dispose();
    _amount.dispose();
    _phone.dispose();
    _daily.dispose();
    _weekly.dispose();
    _monthly.dispose();
    super.dispose();
  }

  bool _adult(UserView user) {
    final raw = user.dateOfBirth;
    if (raw == null) return false;
    final dob = parseDateOfBirth(raw);
    if (dob == null) return false;
    return isOldEnough(dob, DateTime.now().toUtc(), _minAge);
  }

  Future<void> _load() async {
    final session = ref.read(authProvider).value;
    if (session == null) return;
    setState(() => _loading = true);
    try {
      final api = ref.read(arenaApiProvider);
      final balance = await api.walletBalance(session.token);
      final history = await api.walletHistory(session.token, limit: 200);
      final limits = await api.limits(session.token);
      if (!mounted) return;
      setState(() {
        _balance = balance;
        _history = history;
        _limits = limits;
        if (!_limitsFilled) {
          _daily.text = '${limits.daily}';
          _weekly.text = '${limits.weekly}';
          _monthly.text = '${limits.monthly}';
          _limitsFilled = true;
        }
      });
    } on ApiError catch (e) {
      _snack(e.message);
    } on Object {
      _snack('Could not load the wallet. Try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveDob() async {
    final text = _dob.text.trim();
    final parsed = parseDateOfBirth(text);
    if (parsed == null) {
      setState(() => _formError = 'Use a date like 1990-01-01');
      return;
    }
    if (parsed.isAfter(utcDate(DateTime.now()))) {
      setState(() => _formError = 'That date is in the future');
      return;
    }
    setState(() {
      _busy = true;
      _formError = null;
    });
    try {
      await ref.read(authProvider.notifier).setDateOfBirth(text);
    } on ApiError catch (e) {
      if (e.code != ErrorCodes.ageRequired) _snack(e.message);
    } on Object {
      _snack('Could not save. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deposit() async {
    final session = ref.read(authProvider).value;
    if (session == null) return;
    final amount = int.tryParse(_amount.text.trim());
    final msisdn = _phone.text.trim();
    if (amount == null || amount < 500 || amount > 5000000) {
      _snack('Enter an amount from 500 to 5,000,000 UGX');
      return;
    }
    if (!RegExp(r'^256\d{9}$').hasMatch(msisdn)) {
      _snack('Use 256 and then 9 digits');
      return;
    }
    setState(() => _busy = true);
    try {
      final api = ref.read(arenaApiProvider);
      final payment = await api.deposit(
        session.token,
        amount: amount,
        msisdn: msisdn,
      );
      if (payment.status == 'pending' && payment.provider == 'fake') {
        try {
          await api.confirmDeposit(session.token, payment.id);
        } on ApiError catch (e) {
          if (e.status == 404) {
            _snack('The deposit is waiting. No real money moves.');
            return;
          }
          rethrow;
        }
      } else if (payment.status == 'pending') {
        _snack('The deposit is waiting. No real money moves.');
        return;
      }
      _amount.clear();
      await _load();
      _snack('Deposit added. No real money moved.');
    } on ApiError catch (e) {
      _snack(e.message);
    } on Object {
      _snack('Could not deposit. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveLimits() async {
    final session = ref.read(authProvider).value;
    if (session == null) return;
    final daily = int.tryParse(_daily.text.trim());
    final weekly = int.tryParse(_weekly.text.trim());
    final monthly = int.tryParse(_monthly.text.trim());
    if (daily == null || weekly == null || monthly == null) {
      _snack('Enter whole numbers of UGX');
      return;
    }
    setState(() => _busy = true);
    try {
      final saved = await ref
          .read(arenaApiProvider)
          .setLimits(
            session.token,
            daily: daily,
            weekly: weekly,
            monthly: monthly,
          );
      if (!mounted) return;
      setState(() => _limits = saved);
      _snack('Limits saved');
    } on ApiError catch (e) {
      _snack(e.message);
    } on Object {
      _snack('Could not save the limits. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exclude() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Self exclusion'),
        content: const Text(
          'You will not be able to deposit or play a paid table until this '
          'ends. A shorter period does not replace a longer one, and a '
          'permanent exclusion stays.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm-exclude'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Exclude me'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final session = ref.read(authProvider).value;
    if (session == null) return;
    setState(() => _busy = true);
    try {
      final saved = await ref
          .read(arenaApiProvider)
          .selfExclude(session.token, _period);
      if (!mounted) return;
      setState(() => _limits = saved);
      _snack('Self exclusion is in effect');
    } on ApiError catch (e) {
      _snack(e.message);
    } on Object {
      _snack('Could not save. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authProvider).value;
    final user = session?.user;
    final guest = user == null || user.isGuest;
    final adult = user != null && !guest && _adult(user);
    if (adult && !_askedLoad) {
      _askedLoad = true;
      Future.microtask(_load);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Wallet')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (user == null || user.isGuest)
              _loginCard()
            else if (user.dateOfBirth == null)
              _dobForm()
            else if (!adult)
              _ageBlocked()
            else
              ..._walletBody(),
          ],
        ),
      ),
    );
  }

  Widget _loginCard() => Card(
    child: ListTile(
      key: const Key('wallet-login'),
      leading: const Icon(Icons.phone_outlined),
      title: const Text('Play for money'),
      subtitle: const Text(
        'The wallet needs your phone number. No real money moves here.',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push('/login'),
    ),
  );

  Widget _dobForm() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Enter your date of birth. Deposits and paid tables need you to be '
        '$_minAge or older.',
        style: Theme.of(context).textTheme.bodyLarge,
      ),
      const SizedBox(height: 16),
      TextField(
        key: const Key('date-of-birth'),
        controller: _dob,
        keyboardType: TextInputType.datetime,
        decoration: const InputDecoration(
          labelText: 'Date of birth',
          hintText: '1990-01-01',
        ),
      ),
      if (_formError != null) ...[
        const SizedBox(height: 8),
        Text(
          _formError!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ],
      const SizedBox(height: 16),
      FilledButton(
        key: const Key('save-dob'),
        onPressed: _busy ? null : _saveDob,
        child: const Text('Save'),
      ),
    ],
  );

  Widget _ageBlocked() => Card(
    key: const Key('age-blocked'),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        'You must be $_minAge or older to deposit or play a paid table. '
        'The date is stored and cannot be changed here.',
      ),
    ),
  );

  List<Widget> _walletBody() {
    if (_balance == null) {
      return const [
        SizedBox(height: 48),
        Center(child: CircularProgressIndicator()),
      ];
    }
    final excluded = _limits?.excludedAt(DateTime.now().toUtc()) ?? false;
    final pending = _limits?.pending;
    return [
      Text(
        _ugx(_balance!),
        key: const Key('wallet-balance'),
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 4),
      Text('Uganda shillings', style: Theme.of(context).textTheme.bodyMedium),
      const SizedBox(height: 12),
      Text(
        'Time here ${_clock(DateTime.now().difference(_opened))}',
        key: const Key('session-time'),
      ),
      Text('Today ${_ugx(_netToday())}', key: const Key('today-net')),
      const SizedBox(height: 24),
      Text(
        'This is a test deposit. No real money moves.',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      if (excluded) ...[
        const SizedBox(height: 12),
        Text(
          _limits!.permanent
              ? 'Self exclusion is permanent. Deposits are closed.'
              : 'Self exclusion is in effect until '
                    '${formatDateOfBirth(_limits!.excludedUntil!)}. '
                    'Deposits are closed.',
          key: const Key('excluded'),
        ),
      ],
      const SizedBox(height: 12),
      TextField(
        key: const Key('deposit-amount'),
        controller: _amount,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(
          labelText: 'Amount (UGX)',
          hintText: '5000',
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        key: const Key('deposit-phone'),
        controller: _phone,
        keyboardType: TextInputType.phone,
        decoration: const InputDecoration(
          labelText: 'Mobile money number',
          hintText: '256772000001',
        ),
      ),
      const SizedBox(height: 12),
      FilledButton(
        key: const Key('deposit'),
        onPressed: _busy || excluded ? null : _deposit,
        child: const Text('Deposit'),
      ),
      const SizedBox(height: 24),
      Text('History', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      Column(
        key: const Key('wallet-history'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_history.isEmpty)
            const Text('No movements yet')
          else
            for (final entry in _history)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(entry.kind),
                subtitle: Text(_ugx(entry.amount)),
              ),
        ],
      ),
      const SizedBox(height: 24),
      Text('Deposit limits', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      Text(
        'A lower limit applies at once. A higher one waits 24 hours. '
        'The house cap is 1,000,000 UGX a day.',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: 12),
      _limitField('limit-daily', _daily, 'Daily'),
      const SizedBox(height: 12),
      _limitField('limit-weekly', _weekly, 'Weekly'),
      const SizedBox(height: 12),
      _limitField('limit-monthly', _monthly, 'Monthly'),
      if (pending != null) ...[
        const SizedBox(height: 8),
        Text(
          'A higher limit was asked for at ${pending.at.toUtc().toIso8601String()} '
          'and is not in force yet.',
        ),
      ],
      const SizedBox(height: 12),
      FilledButton(
        key: const Key('save-limits'),
        onPressed: _busy ? null : _saveLimits,
        child: const Text('Save limits'),
      ),
      const SizedBox(height: 24),
      Text('Self exclusion', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        key: const Key('self-exclude'),
        initialValue: _period,
        items: const [
          DropdownMenuItem(value: '1d', child: Text('1 day')),
          DropdownMenuItem(value: '7d', child: Text('7 days')),
          DropdownMenuItem(value: '30d', child: Text('30 days')),
          DropdownMenuItem(value: '6m', child: Text('6 months')),
          DropdownMenuItem(value: 'permanent', child: Text('Permanent')),
        ],
        onChanged: _busy ? null : (value) => setState(() => _period = value!),
      ),
      const SizedBox(height: 12),
      OutlinedButton(
        onPressed: _busy ? null : _exclude,
        child: const Text('Exclude me'),
      ),
      if (_loading) const SizedBox(height: 12),
    ];
  }

  Widget _limitField(
    String key,
    TextEditingController controller,
    String label,
  ) => TextField(
    key: Key(key),
    controller: controller,
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    decoration: InputDecoration(labelText: label),
  );

  /// Kampala midnight (UTC+3), the same day boundary the coin reward uses.
  /// Only movements in the loaded history, at most 200, are counted.
  int _netToday() {
    final start = _kampalaDayStart(DateTime.now());
    var sum = 0;
    for (final entry in _history) {
      if (!entry.at.toUtc().isBefore(start)) sum += entry.amount;
    }
    return sum;
  }

  DateTime _kampalaDayStart(DateTime now) {
    const offset = Duration(hours: 3);
    final local = now.toUtc().add(offset);
    return DateTime.utc(local.year, local.month, local.day).subtract(offset);
  }

  String _clock(Duration elapsed) {
    final hours = elapsed.inHours;
    final minutes = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  String _ugx(int amount) {
    final negative = amount < 0;
    final digits = amount.abs().toString();
    final out = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
      out.write(digits[i]);
    }
    return '${negative ? '-' : ''}$out UGX';
  }
}

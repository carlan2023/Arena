import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../online/auth.dart';
import '../online/phone.dart';

/// Phone number, then code, then a name if the account has none
/// (README section 7, first time players).
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

enum _Step { phone, code, name }

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _name = TextEditingController();
  // A phone session without a name resumes at the name step; guests start
  // with their number.
  late _Step _step = switch (ref.read(authProvider).value) {
    final s? when !s.isGuest && !s.hasName => _Step.name,
    _ => _Step.phone,
  };
  bool _leaving = false;
  String? _normalized;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on Object catch (e) {
      if (mounted) setState(() => _error = _describe(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _describe(Object e) => switch (e) {
    AuthException(:final message) => message,
    _ => 'Could not reach Arena. Check your connection and try again.',
  };

  Future<void> _sendCode() => _run(() async {
    final phone = normalizeUgandanPhone(_phone.text);
    if (phone == null) {
      throw const AuthException('Enter a Ugandan mobile number');
    }
    await ref.read(phoneAuthProvider).sendCode(phone);
    setState(() {
      _normalized = phone;
      _step = _Step.code;
    });
  });

  Future<void> _verify() => _run(() async {
    // With a name the router moves on by itself; without one we ask.
    final session = await ref
        .read(authProvider.notifier)
        .login(_normalized!, _code.text.trim());
    if (!session.hasName && mounted) setState(() => _step = _Step.name);
  });

  /// Back to where the player came from: the page that sent them here, or
  /// the one below, or home.
  void _finish() {
    if (!mounted || _leaving) return;
    _leaving = true;
    final GoRouterState route;
    try {
      route = GoRouterState.of(context);
    } on GoError {
      return; // The router already moved on (a redirect ran first).
    }
    final from = route.uri.queryParameters['from'];
    if (from != null) {
      context.go(from);
    } else if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  Future<void> _saveName() => _run(() async {
    final name = _name.text.trim();
    if (name.isEmpty) throw const AuthException('Enter a name');
    await ref.read(authProvider.notifier).setDisplayName(name);
  });

  @override
  Widget build(BuildContext context) {
    // Done once a phone login has a name, however this page was rebuilt.
    final session = ref.watch(authProvider).value;
    if (session != null && !session.isGuest && session.hasName) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _finish());
    }
    final (title, field, button, action) = switch (_step) {
      _Step.phone => (
        'Your phone number',
        TextField(
          key: const Key('phone'),
          controller: _phone,
          keyboardType: TextInputType.phone,
          autofillHints: const [AutofillHints.telephoneNumber],
          decoration: const InputDecoration(
            prefixText: '+256 ',
            hintText: '772 123456',
          ),
          onSubmitted: (_) => _sendCode(),
        ),
        'Send code',
        _sendCode,
      ),
      _Step.code => (
        'Enter the code sent to $_normalized',
        TextField(
          key: const Key('code'),
          controller: _code,
          keyboardType: TextInputType.number,
          maxLength: 6,
          autofillHints: const [AutofillHints.oneTimeCode],
          onSubmitted: (_) => _verify(),
        ),
        'Log in',
        _verify,
      ),
      _Step.name => (
        'What should other players call you?',
        TextField(
          key: const Key('name'),
          controller: _name,
          maxLength: 24,
          onSubmitted: (_) => _saveName(),
        ),
        'Continue',
        _saveName,
      ),
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Arena')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            if (_step == _Step.phone)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Needed for paid tables and the wallet. '
                  'Free games work without it.',
                ),
              ),
            const SizedBox(height: 16),
            field,
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  key: const Key('login-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 24),
            FilledButton(
              key: const Key('login-next'),
              onPressed: _busy ? null : action,
              child: _busy
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(button),
            ),
            if (_step == _Step.code)
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _step = _Step.phone;
                        _code.clear();
                      }),
                child: const Text('Change number'),
              ),
          ],
        ),
      ),
    );
  }
}

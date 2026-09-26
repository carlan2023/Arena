import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../online/config.dart';
import 'router.dart';

/// Links that open the app: the one it was started with, then any that
/// arrive while it runs.
final incomingLinksProvider = Provider<Stream<Uri>>(
  (ref) => AppLinks().uriLinkStream,
);

class ArenaApp extends ConsumerStatefulWidget {
  const ArenaApp({super.key});

  @override
  ConsumerState<ArenaApp> createState() => _ArenaAppState();
}

class _ArenaAppState extends ConsumerState<ArenaApp> {
  StreamSubscription<Uri>? _links;

  @override
  void initState() {
    super.initState();
    _links = ref.read(incomingLinksProvider).listen((uri) {
      final code = roomCodeFromLink(uri);
      if (code != null) ref.read(routerProvider).go('/room/$code');
    }, onError: (Object _) {});
  }

  @override
  void dispose() {
    _links?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Arena',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00695C)),
      ),
      routerConfig: ref.watch(routerProvider),
    );
  }
}

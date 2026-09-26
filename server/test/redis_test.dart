import 'dart:io';

import 'package:arena_server/arena_server.dart';
import 'package:test/test.dart';

void main() {
  final url = Platform.environment['REDIS_URL'];
  final skip = url == null || url.isEmpty ? 'REDIS_URL is not set' : false;

  test('save, load and delete room snapshots', () async {
    final store = await RedisLiveRoomStore.connect(
      url!,
      ttl: const Duration(minutes: 1),
    );
    final code = 'T${DateTime.now().microsecondsSinceEpoch}';
    await store.save(code, {'code': code, 'seq': 1});
    await store.save(code, {'code': code, 'seq': 2});
    final mine = (await store.loadAll()).where((s) => s['code'] == code);
    expect(mine.single['seq'], 2);
    await store.delete(code);
    expect((await store.loadAll()).where((s) => s['code'] == code), isEmpty);
    await store.close();
  }, skip: skip);
}

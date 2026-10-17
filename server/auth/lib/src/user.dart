import 'dart:math';

import 'identity.dart';

class User {
  final String id;

  /// E.164, for example +256772123456. Empty when the login had no phone.
  final String phone;
  final String displayName;

  /// One of the [avatarCount] preset avatars (D35).
  final int avatar;
  final DateTime createdAt;

  const User({
    required this.id,
    required this.phone,
    required this.displayName,
    required this.createdAt,
    this.avatar = 0,
  });

  /// A guest has no verified phone and may only play free games.
  bool get isGuest => phone.isEmpty;

  User copyWith({String? displayName, int? avatar}) => User(
    id: id,
    phone: phone,
    displayName: displayName ?? this.displayName,
    avatar: avatar ?? this.avatar,
    createdAt: createdAt,
  );

  @override
  bool operator ==(Object other) =>
      other is User &&
      other.id == id &&
      other.phone == phone &&
      other.displayName == displayName &&
      other.avatar == avatar &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(id, phone, displayName, avatar, createdAt);

  @override
  String toString() => 'User($id, $phone, $displayName)';
}

abstract interface class UserStore {
  /// Creates the user on first login, keyed by phone (or uid when no phone).
  /// Returns the user.
  Future<User> upsertByIdentity(VerifiedIdentity identity);

  Future<User?> byId(String id);

  /// 1 to 24 characters after trimming, else ArgumentError. StateError for an
  /// unknown id.
  Future<User> setDisplayName(String id, String displayName);

  /// 0 to [avatarCount] - 1, else ArgumentError. StateError for an unknown id.
  Future<User> setAvatar(String id, int avatar);
}

/// Preset avatars, numbered 0 to 15 (D35). No photo upload.
const avatarCount = 16;

/// Throws ArgumentError unless [avatar] is a preset number.
int checkAvatar(int avatar) {
  if (avatar < 0 || avatar >= avatarCount) {
    throw ArgumentError.value(avatar, 'avatar', 'must be 0 to 15');
  }
  return avatar;
}

/// The avatar a new account starts with, at random so a room of new players
/// does not all look the same.
int randomAvatar() => _random.nextInt(avatarCount);

/// "Player " plus the last 4 digits of the phone, or the last 4 characters of
/// the uid when there is no phone.
String defaultDisplayName(VerifiedIdentity identity) {
  final phone = identity.phoneNumber;
  final source = phone != null && phone.isNotEmpty ? phone : identity.uid;
  final tail = source.length <= 4
      ? source
      : source.substring(source.length - 4);
  return 'Player $tail';
}

/// Trims and checks a display name. Throws ArgumentError when it is not 1 to
/// 24 characters or contains control characters.
String normalizeDisplayName(String displayName) {
  final trimmed = displayName.trim();
  final length = trimmed.runes.length;
  if (length < 1 || length > 24) {
    throw ArgumentError.value(
      displayName,
      'displayName',
      'must be 1 to 24 characters',
    );
  }
  if (trimmed.runes.any((r) => r < 0x20 || r == 0x7f)) {
    throw ArgumentError.value(
      displayName,
      'displayName',
      'must not contain control characters',
    );
  }
  return trimmed;
}

final _random = Random.secure();

/// A random UUID v4 string.
String newUserId() {
  final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class InMemoryUserStore implements UserStore {
  final DateTime Function() _clock;
  final _byId = <String, User>{};
  final _idByPhone = <String, String>{};
  final _idByUidWithoutPhone = <String, String>{};

  InMemoryUserStore({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  @override
  Future<User> upsertByIdentity(VerifiedIdentity identity) async {
    final phone = identity.phoneNumber ?? '';
    final index = phone.isNotEmpty ? _idByPhone : _idByUidWithoutPhone;
    final key = phone.isNotEmpty ? phone : identity.uid;
    final existing = index[key];
    if (existing != null) return _byId[existing]!;
    final user = User(
      id: newUserId(),
      phone: phone,
      displayName: defaultDisplayName(identity),
      avatar: randomAvatar(),
      createdAt: _clock().toUtc(),
    );
    _byId[user.id] = user;
    index[key] = user.id;
    return user;
  }

  @override
  Future<User?> byId(String id) async => _byId[id];

  @override
  Future<User> setDisplayName(String id, String displayName) async {
    final name = normalizeDisplayName(displayName);
    final user = _byId[id];
    if (user == null) throw StateError('Unknown user $id');
    return _byId[id] = user.copyWith(displayName: name);
  }

  @override
  Future<User> setAvatar(String id, int avatar) async {
    checkAvatar(avatar);
    final user = _byId[id];
    if (user == null) throw StateError('Unknown user $id');
    return _byId[id] = user.copyWith(avatar: avatar);
  }
}

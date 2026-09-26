import 'dart:convert';

import 'package:ludo_engine/ludo_engine.dart';

/// Thrown when a message or body does not match the protocol.
class ProtocolException implements Exception {
  ProtocolException(this.message);
  final String message;
  @override
  String toString() => 'ProtocolException: $message';
}

typedef Json = Map<String, Object?>;

Json decodeObject(String text) {
  final Object? value;
  try {
    value = jsonDecode(text);
  } on FormatException catch (e) {
    throw ProtocolException('not JSON: ${e.message}');
  }
  if (value is Map<String, Object?>) return value;
  if (value is Map) return value.cast<String, Object?>();
  throw ProtocolException('expected a JSON object');
}

Json asObject(Object? v, String key) {
  if (v is Map<String, Object?>) return v;
  if (v is Map) return v.cast<String, Object?>();
  throw ProtocolException('$key must be an object');
}

String reqString(Json j, String key) {
  final v = j[key];
  if (v is String) return v;
  throw ProtocolException('$key must be a string');
}

String? optString(Json j, String key) {
  final v = j[key];
  if (v == null || v is String) return v as String?;
  throw ProtocolException('$key must be a string or null');
}

int reqInt(Json j, String key) {
  final v = j[key];
  if (v is int) return v;
  throw ProtocolException('$key must be an integer');
}

int? optInt(Json j, String key) {
  final v = j[key];
  if (v == null || v is int) return v as int?;
  throw ProtocolException('$key must be an integer or null');
}

bool reqBool(Json j, String key) {
  final v = j[key];
  if (v is bool) return v;
  throw ProtocolException('$key must be a boolean');
}

List<Object?> reqList(Json j, String key) {
  final v = j[key];
  if (v is List) return v;
  throw ProtocolException('$key must be a list');
}

List<String> reqStringList(Json j, String key) => [
  for (final e in reqList(j, key))
    if (e is String) e else throw ProtocolException('$key must hold strings'),
];

List<int> reqIntList(Json j, String key) => [
  for (final e in reqList(j, key))
    if (e is int) e else throw ProtocolException('$key must hold integers'),
];

PlayerColor parseColor(String name) {
  for (final c in PlayerColor.values) {
    if (c.name == name) return c;
  }
  throw ProtocolException('unknown colour $name');
}

PlayerColor? optColor(Json j, String key) {
  final s = optString(j, key);
  return s == null ? null : parseColor(s);
}

/// Runs an engine fromJson, turning any failure into a [ProtocolException].
T engineValue<T>(String key, T Function() parse) {
  try {
    return parse();
  } on ProtocolException {
    rethrow;
  } catch (e) {
    throw ProtocolException('bad $key: $e');
  }
}

GameState parseState(Object? v, String key) =>
    engineValue(key, () => GameState.fromJson(asObject(v, key)));

GameState? optState(Json j, String key) =>
    j[key] == null ? null : parseState(j[key], key);

List<Move> parseMoves(Json j, String key) => [
  for (final m in reqList(j, key))
    engineValue(key, () => Move.fromJson(asObject(m, key))),
];

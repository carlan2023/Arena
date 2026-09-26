/// Server address, set at build time:
/// `flutter run --dart-define=ARENA_SERVER_URL=http://192.168.1.5:8080`.
/// The default reaches the host machine from the Android emulator (D24).
const String kServerUrl = String.fromEnvironment(
  'ARENA_SERVER_URL',
  defaultValue: 'http://10.0.2.2:8080',
);

/// Room codes: 6 characters from this alphabet (protocol.md).
const String kRoomCodeAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

bool isRoomCode(String code) =>
    code.length == 6 && code.split('').every(kRoomCodeAlphabet.contains);

/// The room code in an invite link, or null. Accepts `https://<host>/r/CODE`
/// and `arena://r/CODE` (protocol amendment 13).
String? roomCodeFromLink(Uri uri) {
  String? code;
  if (uri.scheme == 'arena' &&
      uri.host == 'r' &&
      uri.pathSegments.length == 1) {
    code = uri.pathSegments.single;
  } else if ((uri.scheme == 'https' || uri.scheme == 'http') &&
      uri.pathSegments.length == 2 &&
      uri.pathSegments.first == 'r') {
    code = uri.pathSegments.last;
  }
  if (code == null) return null;
  code = code.toUpperCase();
  return isRoomCode(code) ? code : null;
}

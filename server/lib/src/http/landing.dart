import 'dart:convert';

import 'package:shelf/shelf.dart';

import '../../config.dart';
import '../ids.dart';
import '../rooms/room.dart';

const _escape = HtmlEscape();

/// GET /r/{code}: opens the app through arena://r/{code}, and otherwise
/// points to the download (protocol amendment 13). This is the link people
/// share on WhatsApp, so it must be small and work without the app.
Response landingPage({
  required String code,
  required Room? room,
  required ServerConfig config,
}) {
  if (!isValidRoomCode(code)) {
    return Response.notFound(
      _page('Room not found', '<p>That room link is not valid.</p>', config),
      headers: _headers,
    );
  }
  final appLink = 'arena://r/$code';
  final status = room == null
      ? 'This room has closed or does not exist.'
      : '${room.seated.length} of ${room.seatCount} seats taken.';
  final body =
      '''
<h1>Join room $code</h1>
<p>${_escape.convert(status)}</p>
<p><a class="button" href="${_escape.convert(appLink)}">Open in Arena</a></p>
${_download(config)}
<script>window.location.href = ${jsonEncode(appLink)};</script>
''';
  return Response.ok(
    _page('Arena room $code', body, config),
    headers: _headers,
  );
}

const _headers = {'content-type': 'text/html; charset=utf-8'};

String _download(ServerConfig config) {
  final url = config.appDownloadUrl;
  if (url == null) return '<p>Install the Arena app to play.</p>';
  return '<p>No app yet? <a href="${_escape.convert(url)}">Download Arena</a>, '
      'then open this link again.</p>';
}

String _page(String title, String body, ServerConfig config) =>
    '''
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${_escape.convert(title)}</title>
<style>
body{font-family:sans-serif;max-width:28rem;margin:2rem auto;padding:0 1rem;color:#222}
.button{display:inline-block;padding:.8rem 1.4rem;background:#c62828;color:#fff;border-radius:.5rem;text-decoration:none}
</style>
</head>
<body>
$body
</body>
</html>
''';

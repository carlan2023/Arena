import 'package:shelf/shelf.dart';

/// Default browser origins: the Firebase web app and local development.
const List<String> kDefaultAllowedOrigins = [
  'https://arena-cddfa.web.app',
  'https://arena-cddfa.firebaseapp.com',
  'http://localhost:*',
];

/// Whether [origin] matches one of [allowed]. A pattern ending in `:*`
/// matches any port, or none, on that scheme and host.
bool originAllowed(String origin, List<String> allowed) {
  for (final pattern in allowed) {
    if (pattern == origin) return true;
    if (pattern.endsWith(':*')) {
      final base = pattern.substring(0, pattern.length - 2);
      if (origin == base) return true;
      if (origin.startsWith('$base:') &&
          int.tryParse(origin.substring(base.length + 1)) != null) {
        return true;
      }
    }
  }
  return false;
}

/// Answers preflight requests and adds Access-Control-Allow-Origin for
/// allowed origins. Requests without an Origin (the app, curl) pass as is.
Middleware cors(List<String> allowed) {
  return (inner) => (req) async {
    final origin = req.headers['origin'];
    final ok = origin != null && originAllowed(origin, allowed);
    if (req.method == 'OPTIONS' && origin != null) {
      if (!ok) return Response.forbidden('origin not allowed');
      return Response(
        204,
        headers: {
          ..._headers(origin),
          'access-control-allow-methods':
              'GET, POST, PUT, PATCH, DELETE, OPTIONS',
          'access-control-allow-headers': 'authorization, content-type',
          'access-control-max-age': '600',
        },
      );
    }
    final res = await inner(req);
    return ok ? res.change(headers: _headers(origin)) : res;
  };
}

Map<String, String> _headers(String origin) => {
  'access-control-allow-origin': origin,
  'vary': 'Origin',
};

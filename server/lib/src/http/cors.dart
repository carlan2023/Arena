import 'package:shelf/shelf.dart';

/// Browser origins allowed to call the API and open the web socket
/// (ALLOWED_ORIGINS). An entry is an exact origin such as
/// `https://arena-cddfa.web.app`, or one ending in `:*` to allow any port of
/// that host, such as `http://localhost:*`.
class OriginPolicy {
  OriginPolicy(List<String> patterns)
    : _exact = {
        for (final p in patterns)
          if (!p.endsWith(':*')) _normalize(p),
      },
      _anyPort = [
        for (final p in patterns)
          if (p.endsWith(':*')) _normalize(p.substring(0, p.length - 2)),
      ];

  final Set<String> _exact;
  final List<String> _anyPort;

  static String _normalize(String origin) =>
      origin.trim().toLowerCase().replaceAll(RegExp(r'/+$'), '');

  bool allows(String origin) {
    final o = _normalize(origin);
    if (_exact.contains(o)) return true;
    for (final base in _anyPort) {
      if (o == base) return true;
      if (o.startsWith('$base:') &&
          int.tryParse(o.substring(base.length + 1)) != null) {
        return true;
      }
    }
    return false;
  }
}

const _allowMethods = 'GET, POST, PUT, PATCH, DELETE, OPTIONS';
const _allowHeaders = 'authorization, content-type';

/// Answers preflight requests and adds Access-Control-Allow-Origin for allowed
/// origins. Requests without an Origin header (the Android app, curl, payment
/// callbacks) pass through untouched.
Middleware cors(OriginPolicy policy) {
  return (inner) => (req) async {
    final origin = req.headers['origin'];
    if (origin == null) return inner(req);
    final allowed = policy.allows(origin);
    if (req.method == 'OPTIONS') {
      if (!allowed) {
        return Response.forbidden(null, headers: {'vary': 'Origin'});
      }
      return Response(
        204,
        headers: {
          'access-control-allow-origin': origin,
          'access-control-allow-methods': _allowMethods,
          'access-control-allow-headers': _allowHeaders,
          'access-control-max-age': '600',
          'vary': 'Origin',
        },
      );
    }
    final res = await inner(req);
    if (!allowed) return res.change(headers: {'vary': 'Origin'});
    return res.change(
      headers: {'access-control-allow-origin': origin, 'vary': 'Origin'},
    );
  };
}

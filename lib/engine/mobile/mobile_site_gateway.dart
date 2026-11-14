import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/errors/engine_exception.dart';
import '../models.dart';
import 'mobile_engine.dart';
import 'mobile_parsers.dart';

/// Plain-HTTP search backend for the mobile engine.
///
/// Search merges the six-entry suggest endpoint with the site's paginated
/// `/tim-kiem/` results. The permanent gateway redirects to the current live
/// domain; that origin is cached for the rest of the session and used to
/// resolve relative result links. Redirects are followed manually because the
/// suggest endpoint requires a POST and the gateway only preserves the host,
/// not the path.
class MobileSiteGateway implements MobileSearchSource {
  MobileSiteGateway({
    http.Client? client,
    Uri? gateway,
    Future<Uri> Function()? originResolver,
    Duration timeout = const Duration(seconds: 20),
    int maxSearchPages = 10,
  })  : _client = client ?? http.Client(),
        _gateway = gateway ?? Uri.parse('https://animevietsub.fan'),
        _originResolver = originResolver,
        _timeout = timeout,
        _maxSearchPages = maxSearchPages < 1 ? 1 : maxSearchPages;

  static const String _userAgent =
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36';
  static const Map<String, String> _searchHeaders = <String, String>{
    'User-Agent': _userAgent,
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'vi,en;q=0.9',
  };
  static const String _challengeMessage =
      'Unexpected search response: the site may be unavailable or showing a '
      'security challenge. Try again later.';

  final http.Client _client;
  final Uri _gateway;
  final Future<Uri> Function()? _originResolver;
  final Duration _timeout;
  final int _maxSearchPages;
  final Map<String, Map<String, String>> _cookies =
      <String, Map<String, String>>{};

  Uri? _origin;

  @override
  Future<List<AnimeSummary>> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const <AnimeSummary>[];

    final origin = await _resolveOrigin();

    // Run both sources concurrently: suggestions are fast but incomplete,
    // while the full search pages may be slower and occasionally fail.
    final suggestAttempt = _attempt(_fetchSuggestions(origin, q));
    final pageAttempt = _attempt(_fetchSearchPages(origin, q));
    final suggested = await suggestAttempt;
    final pages = await pageAttempt;

    final results = <AnimeSummary>[];
    final seen = <String>{};
    for (final summary in <AnimeSummary>[
      ...?suggested.value,
      ...?pages.value?.rows,
    ]) {
      if (summary.url.isEmpty || !seen.add(summary.url)) continue;
      results.add(summary);
    }
    if (results.isNotEmpty) return results;

    final page = pages.value;
    final validEmpty =
        page != null && (page.noResults || suggested.value != null);
    if (validEmpty) return const <AnimeSummary>[];

    throw pages.error ?? suggested.error ?? _challengeException();
  }

  Future<List<AnimeSummary>> _fetchSuggestions(
    Uri origin,
    String query,
  ) async {
    final base = _origin ?? origin;
    final uri = base.replace(path: '/ajax/suggest');
    final response = await _sendFollowingRedirects(
      uri,
      (target) => http.Request('POST', target)
        ..followRedirects = false
        ..headers.addAll(<String, String>{
          'User-Agent': _userAgent,
          'X-Requested-With': 'XMLHttpRequest',
        })
        ..bodyFields = <String, String>{
          'ajaxSearch': '1',
          'keysearch': query,
        },
    );
    _ensureSuccess(response, uri);
    return parseMobileSearch(response.body, baseUri: _origin ?? origin);
  }

  Future<MobileSearchPage> _fetchSearchPages(Uri origin, String query) async {
    final first = await _fetchSearchPage(origin, query, 1);
    final last = first.pages < _maxSearchPages ? first.pages : _maxSearchPages;
    final rows = <AnimeSummary>[...first.rows];

    if (last > 1) {
      // Follow a few pages concurrently. A transient failure on one page must
      // not discard the results that already loaded.
      var next = 2;
      Future<void> worker() async {
        while (true) {
          final page = next;
          if (page > last) return;
          next++;
          try {
            rows.addAll((await _fetchSearchPage(origin, query, page)).rows);
          } catch (_) {
            // Keep the pages that succeeded.
          }
        }
      }

      final workers = last - 1 < 4 ? last - 1 : 4;
      await Future.wait(<Future<void>>[
        for (var index = 0; index < workers; index++) worker(),
      ]);
    }

    return MobileSearchPage(
      rows: rows,
      pages: first.pages,
      noResults: first.noResults && rows.isEmpty,
    );
  }

  Future<MobileSearchPage> _fetchSearchPage(
    Uri origin,
    String query,
    int page,
  ) async {
    final base = _origin ?? origin;
    final uri = Uri.parse('${base.toString()}${_searchPagePath(query, page)}');
    final response = await _sendFollowingRedirects(
      uri,
      (target) => http.Request('GET', target)
        ..followRedirects = false
        ..headers.addAll(_searchHeaders),
    );
    _ensureSuccess(response, uri);
    return parseMobileSearchPage(response.body, baseUri: _origin ?? origin);
  }

  Future<http.Response> _sendFollowingRedirects(
    Uri uri,
    http.BaseRequest Function(Uri target) buildRequest,
  ) async {
    var current = uri;
    for (var attempt = 0; attempt < 4; attempt++) {
      final response = await _perform(current, () => buildRequest(current));
      final redirected = _redirectTarget(current, response);
      if (redirected == null) return response;
      _origin = redirected;
      current = redirected.replace(
        path: uri.path,
        query: uri.hasQuery ? uri.query : null,
      );
    }
    throw EngineException(
      EngineErrorKind.network,
      'Search was redirected too many times. The site gateway may be '
      'misconfigured; try again later.',
    );
  }

  Future<http.Response> _perform(
    Uri uri,
    http.BaseRequest Function() buildRequest,
  ) async {
    Future<http.Response> send() async {
      final request = buildRequest();
      final cookie = _cookieHeader(uri);
      if (cookie.isNotEmpty) request.headers['Cookie'] = cookie;

      try {
        final streamed = await _client.send(request).timeout(_timeout);
        final response =
            await http.Response.fromStream(streamed).timeout(_timeout);
        _storeCookies(uri, response);
        return response;
      } on TimeoutException catch (error, stackTrace) {
        throw EngineException(
          EngineErrorKind.timeout,
          'Search timed out after ${_timeout.inSeconds}s.',
          cause: error,
          stackTrace: stackTrace,
        );
      } on SocketException catch (error, stackTrace) {
        throw EngineException(
          EngineErrorKind.network,
          'Could not reach ${uri.host}: ${error.message}',
          cause: error,
          stackTrace: stackTrace,
        );
      } on http.ClientException catch (error, stackTrace) {
        throw EngineException(
          EngineErrorKind.network,
          'Could not reach ${uri.host}: ${error.message}',
          cause: error,
          stackTrace: stackTrace,
        );
      }
    }

    var response = await send();
    if (response.statusCode == 403 &&
        _isChallenge(response.body) &&
        _cookieHeader(uri).isNotEmpty) {
      response = await send();
    }
    return response;
  }

  void _ensureSuccess(http.Response response, Uri uri) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    throw EngineException(
      EngineErrorKind.network,
      'Search returned HTTP ${response.statusCode} from ${uri.host}. '
      'Check site availability and proxy/VPN settings.',
    );
  }

  void _storeCookies(Uri uri, http.Response response) {
    final entries =
        response.headersSplitValues['set-cookie'] ?? const <String>[];
    if (entries.isEmpty) return;

    final jar = _cookies.putIfAbsent(
      uri.host.toLowerCase(),
      () => <String, String>{},
    );
    for (final entry in entries) {
      final pair = entry.split(';').first;
      final separator = pair.indexOf('=');
      if (separator <= 0) continue;
      final name = pair.substring(0, separator).trim();
      final value = pair.substring(separator + 1).trim();
      if (name.isEmpty) continue;
      jar[name] = value;
    }
  }

  String _cookieHeader(Uri uri) {
    final jar = _cookies[uri.host.toLowerCase()];
    if (jar == null || jar.isEmpty) return '';
    return jar.entries.map((entry) => '${entry.key}=${entry.value}').join('; ');
  }

  static bool _isChallenge(String body) =>
      body.length < 4096 &&
      RegExp(r'window\.location(?:\.href)?\s*=').hasMatch(body);

  static String _searchPagePath(String query, int page) {
    final base = '/tim-kiem/${Uri.encodeComponent(query)}/';
    return page <= 1 ? base : '${base}trang-$page.html';
  }

  Uri? _redirectTarget(Uri requestUri, http.Response response) {
    if (response.statusCode != 301 &&
        response.statusCode != 302 &&
        response.statusCode != 303 &&
        response.statusCode != 307 &&
        response.statusCode != 308) {
      return null;
    }
    final location = response.headers['location']?.trim() ?? '';
    if (location.isEmpty) return null;
    final target = requestUri.resolve(location);
    if (target.host.isEmpty || target.host == requestUri.host) return null;
    return _normalize(target);
  }

  Future<Uri> _resolveOrigin() async {
    final cached = _origin;
    if (cached != null) return cached;

    final resolver = _originResolver;
    if (resolver != null) {
      return _origin = _normalize(await resolver());
    }
    return _origin = _normalize(_gateway);
  }

  static EngineException _challengeException() => EngineException(
        EngineErrorKind.protocol,
        _challengeMessage,
      );

  static Uri _normalize(Uri uri) => Uri(
        scheme: uri.scheme,
        userInfo: uri.userInfo.isEmpty ? null : uri.userInfo,
        host: uri.host,
        port: uri.hasPort ? uri.port : null,
      );
}

class _Attempt<T> {
  const _Attempt.value(this.value) : error = null;
  const _Attempt.error(this.error) : value = null;

  final T? value;
  final EngineException? error;
}

Future<_Attempt<T>> _attempt<T>(Future<T> future) async {
  try {
    return _Attempt<T>.value(await future);
  } on EngineException catch (error) {
    return _Attempt<T>.error(error);
  } catch (error, stackTrace) {
    return _Attempt<T>.error(EngineException(
      EngineErrorKind.network,
      'Search failed: $error',
      cause: error,
      stackTrace: stackTrace,
    ));
  }
}

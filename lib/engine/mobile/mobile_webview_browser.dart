import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../core/errors/engine_exception.dart';
import '../../core/logging/app_logger.dart';
import 'mobile_engine.dart';
import 'mobile_parsers.dart';

/// Headless Android WebView used for pages that reject plain HTTP clients.
///
/// Each operation gets its own WebView, mirroring the desktop engine's
/// Playwright lifecycle. Android's shared cookie store keeps Cloudflare
/// clearance between operations, so the cost is mostly WebView startup.
class MobileWebViewBrowser implements MobilePageBrowser {
  MobileWebViewBrowser({
    this.navigationTimeout = const Duration(seconds: 45),
    this.contentTimeout = const Duration(seconds: 20),
    this.pollInterval = const Duration(milliseconds: 300),
    this.logger,
  });

  final Duration navigationTimeout;
  final Duration contentTimeout;
  final Duration pollInterval;
  final AppLogger? logger;

  @override
  Future<List<Object?>> fetchEpisodeRows(String animeUrl) async {
    final page = mobileAnimePageUrl(animeUrl);
    return _withPage<List<Object?>>(page, (controller) async {
      final found = await _waitForCount(
        controller,
        'document.querySelectorAll("li.episode a").length',
      );
      if (!found) {
        final diagnostics = await _diagnostics(controller);
        if (isMobileChallengePage(
          title: diagnostics.title,
          bodyText: diagnostics.body,
        )) {
          throw EngineException(
            EngineErrorKind.network,
            'Cloudflare challenge detected while loading episodes. Disable '
            'VPN/proxy or try a different connection.',
            details: page.toString(),
          );
        }
        throw EngineException(
          EngineErrorKind.parse,
          'The episode list did not appear on the page. The site may be '
          'unavailable or its layout changed.',
          details: '${page.host}${page.path} · ${diagnostics.title}',
        );
      }

      final raw = await controller.evaluateJavascript(source: '''
        (() => JSON.stringify(
          Array.from(document.querySelectorAll('li.episode a')).map((a) => ({
            title: (a.textContent || '').trim(),
            name: (a.getAttribute('title') || '').trim(),
            url: a.href || '',
          }))
        ))()
      ''');
      final decoded = _decodeJson(raw);
      if (decoded is! List) {
        throw EngineException(
          EngineErrorKind.parse,
          'The episode list could not be read from the page.',
        );
      }
      return decoded;
    });
  }

  @override
  Future<String> resolvePlayer(String episodeUrl) async {
    final episodeId = mobileEpisodeId(episodeUrl);
    if (episodeId == null) {
      throw EngineException(
        EngineErrorKind.parse,
        'The episode URL does not contain a stream id.',
        details: episodeUrl,
      );
    }
    final page = mobileEpisodePageUrl(episodeUrl);

    return _withPage<String>(page, (controller) async {
      await _ensureChallengeResolved(controller);

      final backup = await _postPlayer(controller, <String, String>{
        'episodeId': episodeId,
        'backup': '1',
      });
      final backupJson = _decodeJson(backup);
      if (backupJson is! Map || !_truthy(backupJson['success'])) {
        final snippet = _snippet(backup);
        _logFailure('Mobile backup lookup failed', episodeId, snippet);
        throw EngineException(
          EngineErrorKind.protocol,
          'The site failed to load its backup server list.',
          details: 'episodeId=$episodeId · $snippet',
        );
      }
      final servers = parseMobilePlayerServers('${backupJson['html'] ?? ''}');
      if (servers.isEmpty) {
        final snippet = _snippet('${backupJson['html'] ?? ''}');
        _logFailure('Mobile player servers missing', episodeId, snippet);
        throw EngineException(
          EngineErrorKind.protocol,
          'No playable server was offered for this episode.',
          details: snippet,
        );
      }

      // Prefer the site's API servers, which use a reachable CDN; fall through
      // to the remaining servers when one returns no link. Some networks
      // refuse the HDX/ADS host outright, so never trust the first entry.
      Object? lastStream;
      String? unreachableLink;
      for (final server in servers) {
        Object? stream;
        try {
          stream = await _postPlayer(controller, <String, String>{
            'link': server.href,
            'play': server.play,
            'id': server.id,
            'backuplinks': '1',
          });
        } on Object catch (error) {
          (logger ?? AppLogger.instance).warning(
            'Mobile player server failed',
            error: error,
            context: <String, Object?>{
              'episodeId': episodeId,
              'server': server.label,
            },
          );
          continue;
        }
        lastStream = stream;
        final link = tryParseMobilePlayerLink(_decodeJson(stream));
        if (link == null) continue;
        if (await _isReachable(link)) return link;

        // Remember the first link so the player can still surface a useful
        // retry screen when every server refuses connections.
        unreachableLink ??= link;
        (logger ?? AppLogger.instance).warning(
          'Mobile player host unreachable',
          context: <String, Object?>{
            'episodeId': episodeId,
            'server': server.label,
            'host': Uri.tryParse(link)?.host ?? link,
          },
        );
      }
      if (unreachableLink != null) return unreachableLink;

      final snippet = _snippet(lastStream);
      _logFailure('Mobile player link missing', episodeId, snippet);
      throw EngineException(
        EngineErrorKind.protocol,
        'The site did not return a playable stream link.',
        details: snippet,
      );
    });
  }

  /// TCP-level probe before handing a URL to the player WebView.
  ///
  /// A player host can be blocked on a carrier while the site itself works
  /// (`net::ERR_CONNECTION_REFUSED`), so skip servers that cannot be reached
  /// and let the next candidate try.
  static Future<bool> _isReachable(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return false;
    final port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
    Socket? socket;
    try {
      socket = await Socket.connect(
        uri.host,
        port,
        timeout: const Duration(seconds: 5),
      );
      return true;
    } on Object {
      return false;
    } finally {
      socket?.destroy();
    }
  }

  void _logFailure(String message, String episodeId, String snippet) {
    (logger ?? AppLogger.instance).error(
      message,
      context: <String, Object?>{
        'episodeId': episodeId,
        'response': snippet,
      },
    );
  }

  static String _snippet(Object? value) {
    final text = '$value'.replaceAll(RegExp(r'\s+'), ' ').trim();
    return text.length <= 300 ? text : '${text.substring(0, 300)}…';
  }

  static bool _truthy(Object? value) => switch (value) {
        null => false,
        bool result => result,
        num result => result != 0,
        String result =>
          result.isNotEmpty && result != '0' && result.toLowerCase() != 'false',
        _ => true,
      };

  @override
  Future<void> dispose() async {
    // WebViews are created per operation and disposed in `_withPage`.
  }

  Future<T> _withPage<T>(
    Uri uri,
    Future<T> Function(InAppWebViewController controller) action,
  ) async {
    final loaded = Completer<void>();
    EngineException? loadError;
    HeadlessInAppWebView? webView;

    try {
      webView = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(uri.toString())),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          domStorageEnabled: true,
          databaseEnabled: true,
          thirdPartyCookiesEnabled: true,
          mediaPlaybackRequiresUserGesture: false,
          allowsInlineMediaPlayback: true,
          isInspectable: kDebugMode,
        ),
        onLoadStop: (controller, url) {
          if (!loaded.isCompleted) loaded.complete();
        },
        onReceivedError: (controller, request, error) {
          if (request.isForMainFrame == true && loadError == null) {
            loadError = EngineException(
              EngineErrorKind.network,
              'Could not load ${uri.host}: ${error.description}',
              details: error.description,
            );
            if (!loaded.isCompleted) loaded.complete();
          }
        },
      );
      await webView.run();

      final outcome = await Future.any<Object?>(<Future<Object?>>[
        loaded.future,
        Future<void>.delayed(navigationTimeout),
      ]);
      if (loadError != null) throw loadError!;
      if (outcome == null && !loaded.isCompleted) {
        throw EngineException(
          EngineErrorKind.timeout,
          'Loading ${uri.host} timed out after '
          '${navigationTimeout.inSeconds}s.',
        );
      }

      final controller = webView.webViewController;
      if (controller == null) {
        throw EngineException(
          EngineErrorKind.spawnFailed,
          'The Android WebView could not be created.',
        );
      }
      return await action(controller);
    } finally {
      try {
        await webView?.dispose();
      } on Object {
        // Disposal failures must not mask the real error.
      }
    }
  }

  Future<bool> _waitForCount(
    InAppWebViewController controller,
    String expression,
  ) async {
    final deadline = DateTime.now().add(contentTimeout);
    while (DateTime.now().isBefore(deadline)) {
      try {
        final value = await controller.evaluateJavascript(source: expression);
        final count = value is num
            ? value.toInt()
            : int.tryParse('$value'.replaceAll('"', '')) ?? 0;
        if (count > 0) return true;
      } on Object {
        // A navigation can destroy the execution context mid-poll; retry.
      }
      await Future<void>.delayed(pollInterval);
    }
    return false;
  }

  Future<void> _ensureChallengeResolved(
    InAppWebViewController controller,
  ) async {
    final deadline = DateTime.now().add(contentTimeout);
    var diagnostics = const _PageDiagnostics(title: '', body: '');
    while (DateTime.now().isBefore(deadline)) {
      try {
        diagnostics = await _diagnostics(controller);
        if (diagnostics.body.isEmpty &&
            !isMobileChallengePage(
              title: diagnostics.title,
              bodyText: diagnostics.body,
            )) {
          await Future<void>.delayed(pollInterval);
          continue;
        }
        if (!isMobileChallengePage(
          title: diagnostics.title,
          bodyText: diagnostics.body,
        )) {
          return;
        }
      } on Object {
        // The document is still navigating.
      }
      await Future<void>.delayed(pollInterval);
    }
    throw EngineException(
      EngineErrorKind.network,
      'Cloudflare is still checking this connection. Disable VPN/proxy or '
      'try a different network.',
      details: diagnostics.title,
    );
  }

  Future<_PageDiagnostics> _diagnostics(
    InAppWebViewController controller,
  ) async {
    final raw = await controller.evaluateJavascript(source: '''
      (() => JSON.stringify({
        title: document.title || '',
        body: document.body ? (document.body.innerText || '').slice(0, 4000) : '',
      }))()
    ''');
    final decoded = _decodeJson(raw);
    if (decoded is Map) {
      return _PageDiagnostics(
        title: '${decoded['title'] ?? ''}',
        body: '${decoded['body'] ?? ''}',
      );
    }
    return const _PageDiagnostics(title: '', body: '');
  }

  Future<Object?> _postPlayer(
    InAppWebViewController controller,
    Map<String, String> body,
  ) async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      final result = await controller.callAsyncJavaScript(
        functionBody: r'''
const response = await fetch('/ajax/player', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
    'X-Requested-With': 'XMLHttpRequest',
  },
  body: new URLSearchParams(body),
});
if (!response.ok) {
  throw new Error('Stream API returned HTTP ' + response.status);
}
return await response.text();
''',
        arguments: <String, dynamic>{
          'body': body,
        },
      );
      if (result == null) {
        lastError = 'The WebView returned no response.';
      } else if (result.error != null) {
        lastError = result.error;
        final message = result.error!;
        if (message.contains('Failed to fetch') ||
            message.contains('HTTP 403') ||
            message.contains('HTTP 503')) {
          await Future<void>.delayed(pollInterval);
          continue;
        }
        throw EngineException(
          EngineErrorKind.network,
          'The stream request failed: $message',
        );
      } else {
        return result.value;
      }
      await Future<void>.delayed(pollInterval);
    }
    throw EngineException(
      EngineErrorKind.network,
      'The stream request kept failing. The site may be blocking this '
      'connection.',
      details: '$lastError',
    );
  }

  static Object? _decodeJson(Object? raw) {
    if (raw is! String) return raw;
    final value = raw.trim();
    if (value.isEmpty) return null;
    try {
      return jsonDecode(value);
    } on FormatException {
      return raw;
    }
  }
}

class _PageDiagnostics {
  const _PageDiagnostics({required this.title, required this.body});

  final String title;
  final String body;
}

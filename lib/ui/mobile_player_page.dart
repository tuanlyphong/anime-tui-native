import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/logging/app_logger.dart';
import '../engine/engine_client.dart';
import '../engine/mobile/mobile_parsers.dart';
import '../engine/models.dart';

/// Build the wrapper document used by [MobilePlayerPage].
///
/// Some stream hosts refuse to run when opened top-level and replace the page
/// with "Video chỉ có thể phát trong iframe." Embedding the stream reproduces
/// the site's own player context, where the host allows playback.
@visibleForTesting
String buildMobilePlayerDocument(String streamUrl) {
  final src = const HtmlEscape(HtmlEscapeMode.attribute).convert(streamUrl);
  return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
  <style>
    html, body { margin: 0; padding: 0; height: 100%; background: #000; overflow: hidden; }
    iframe { position: fixed; inset: 0; width: 100%; height: 100%; border: 0; }
  </style>
</head>
<body>
  <iframe src="$src" allow="autoplay; fullscreen; encrypted-media; picture-in-picture" allowfullscreen></iframe>
</body>
</html>
''';
}

/// Script injected into every frame of the player WebView.
///
/// The stream host embeds its advertising configuration in the page and turns
/// it into a clickable overlay when playback pauses. Deleting `pauseAd` while
/// the configuration is parsed prevents that overlay from being created. The
/// DOM scrub is a fallback for players that build the overlay another way.
@visibleForTesting
String buildMobilePlayerAdBlockScript() => r'''
(function () {
  if (window.__animeTuiAdBlockInstalled) return;
  window.__animeTuiAdBlockInstalled = true;

  // Player code: JSON.parse(atob(adsConfig)). Strip the pause ad before it is
  // ever handed to the player UI.
  try {
    var originalParse = JSON.parse;
    JSON.parse = function (text, reviver) {
      var value = originalParse.call(JSON, text, reviver);
      if (value && typeof value === 'object' && !Array.isArray(value)) {
        try { delete value.pauseAd; } catch (error) {}
        if (value.pauseAd) value.pauseAd = null;
      }
      return value;
    };
  } catch (error) {}

  var AD_SELECTOR = [
    'a[href*="adqc.net"]',
    'a[href*="bom88."]',
    'img[src*="lh3.googleusercontent.com"]',
    '[class*="pause-ad"]',
    '[class*="pauseAd"]',
    '[id*="pause-ad"]',
    '[id*="pauseAd"]'
  ].join(',');

  function isAdNode(node) {
    if (!node || node.nodeType !== 1) return false;
    if (node.matches && node.matches(AD_SELECTOR)) return true;
    return false;
  }

  function removeNode(node) {
    var parent = node.parentElement;
    try {
      node.remove();
    } catch (error) {
      node.style.display = 'none';
    }
    // Drop an empty wrapper left behind by the removed ad markup.
    if (parent && parent !== document.body &&
        parent !== document.documentElement &&
        parent.childElementCount === 0 &&
        (parent.textContent || '').trim() === '') {
      try { parent.remove(); } catch (error) {}
    }
  }

  function scrub(root) {
    if (!root || !root.querySelectorAll) return;
    var nodes = root.querySelectorAll(AD_SELECTOR);
    for (var i = nodes.length - 1; i >= 0; i--) removeNode(nodes[i]);
  }

  function start() {
    scrub(document);
    var observer = new MutationObserver(function (mutations) {
      for (var i = 0; i < mutations.length; i++) {
        var added = mutations[i].addedNodes;
        for (var j = 0; j < added.length; j++) {
          var node = added[j];
          if (node.nodeType !== 1) continue;
          if (isAdNode(node)) {
            removeNode(node);
          } else {
            scrub(node);
          }
        }
      }
    });
    observer.observe(document.documentElement || document, {
      childList: true,
      subtree: true
    });
  }

  if (document.documentElement) {
    start();
  } else {
    document.addEventListener('DOMContentLoaded', start, {once: true});
  }

  // Never navigate to the ad landing page if a click slips through first.
  document.addEventListener('click', function (event) {
    var anchor = event.target && event.target.closest
      ? event.target.closest('a[href]')
      : null;
    if (!anchor) return;
    var href = anchor.getAttribute('href') || '';
    if (href.indexOf('adqc.net') !== -1 || href.indexOf('bom88.') !== -1) {
      event.preventDefault();
      event.stopPropagation();
    }
  }, true);
})();
''';

/// User scripts installed in the player WebView.
///
/// Player documents embed their video in a cross-origin iframe, so the ad
/// script has to run in every frame (`forMainFrameOnly: false`).
@visibleForTesting
List<UserScript> buildMobilePlayerUserScripts() => <UserScript>[
      UserScript(
        source: buildMobilePlayerAdBlockScript(),
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        forMainFrameOnly: false,
      ),
    ];

/// Open the mobile player as a [PlaybackSession].
///
/// The route completes with the outcome chosen by the user (finished, stopped,
/// or failed) and the controller treats it like any other player process.
PlaybackSession openMobilePlaybackSession(
  BuildContext context,
  PlaybackRequest request, {
  AppLogger? logger,
}) {
  final navigator = Navigator.of(context, rootNavigator: true);
  final statuses = StreamController<PlaybackStatus>.broadcast();
  final result = Completer<PlaybackResult>();

  void publish(PlaybackStatus status) {
    if (!statuses.isClosed) statuses.add(status);
  }

  final route = MaterialPageRoute<PlaybackResult>(
    fullscreenDialog: true,
    builder: (_) => MobilePlayerPage(
      request: request,
      onStatus: publish,
      logger: logger,
    ),
  );

  navigator.push<PlaybackResult>(route).then(
    (outcome) {
      if (!result.isCompleted) {
        result.complete(
          outcome ?? const PlaybackResult(outcome: PlaybackOutcome.stopped),
        );
      }
      unawaited(statuses.close());
    },
    onError: (Object error, StackTrace stackTrace) {
      if (!result.isCompleted) {
        result.complete(PlaybackResult(
          outcome: PlaybackOutcome.failed,
          error: '$error',
        ));
      }
      unawaited(statuses.close());
    },
  );

  return PlaybackSession(
    statuses: statuses.stream,
    result: result.future,
    stop: () async {
      if (route.isActive) {
        navigator.pop(
          const PlaybackResult(outcome: PlaybackOutcome.stopped),
        );
      }
    },
  );
}

class MobilePlayerPage extends StatefulWidget {
  const MobilePlayerPage({
    super.key,
    required this.request,
    this.onStatus,
    this.logger,
  });

  final PlaybackRequest request;
  final ValueChanged<PlaybackStatus>? onStatus;
  final AppLogger? logger;

  @override
  State<MobilePlayerPage> createState() => _MobilePlayerPageState();
}

class _MobilePlayerPageState extends State<MobilePlayerPage> {
  InAppWebViewController? _controller;
  double _progress = 0;
  bool _loading = true;
  String? _loadError;

  String get _url => widget.request.streamUrl;

  /// Episode page used as the wrapper's base URL and browser fallback.
  ///
  /// The player expects to be embedded by the episode page, so this also gives
  /// the iframe request a sensible referrer instead of the stream URL itself.
  String? get _episodePageUrl {
    final raw = widget.request.episodeUrl.trim();
    if (raw.isEmpty) return null;
    final uri = Uri.tryParse(raw);
    if (uri == null) return null;
    if (uri.scheme == 'http' || uri.scheme == 'https') return uri.toString();
    return mobileEpisodePageUrl(raw).toString();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          widget.request.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15),
        ),
        actions: [
          IconButton(
            tooltip: 'Open in browser',
            onPressed: () => unawaited(_openExternal()),
            icon: const Icon(Icons.open_in_browser),
          ),
          PopupMenuButton<String>(
            tooltip: 'Player options',
            onSelected: (value) {
              if (value == 'finished') _finish();
            },
            itemBuilder: (context) => const <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'finished',
                child: ListTile(
                  leading: Icon(Icons.check_circle_outline),
                  title: Text('Mark finished'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            InAppWebView(
              initialData: InAppWebViewInitialData(
                data: buildMobilePlayerDocument(_url),
                mimeType: 'text/html',
                encoding: 'utf-8',
                baseUrl: WebUri(_episodePageUrl ?? _url),
              ),
              initialUserScripts: UnmodifiableListView<UserScript>(
                buildMobilePlayerUserScripts(),
              ),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                domStorageEnabled: true,
                databaseEnabled: true,
                thirdPartyCookiesEnabled: true,
                mediaPlaybackRequiresUserGesture: false,
                allowsInlineMediaPlayback: true,
                useHybridComposition: true,
                supportZoom: false,
                isInspectable: kDebugMode,
              ),
              onWebViewCreated: (controller) {
                _controller = controller;
              },
              onLoadStart: (controller, url) {
                if (!mounted) return;
                setState(() {
                  _loading = true;
                  _loadError = null;
                  _progress = 0;
                });
                widget.onStatus?.call(const PlaybackStatus(
                  stage: PlaybackStage.preparing,
                  text: 'Loading player…',
                ));
              },
              onProgressChanged: (controller, progress) {
                if (!mounted) return;
                setState(() => _progress = progress / 100);
              },
              onLoadStop: (controller, url) {
                if (!mounted) return;
                setState(() {
                  _loading = false;
                  _progress = 1;
                });
                widget.onStatus?.call(const PlaybackStatus(
                  stage: PlaybackStage.playing,
                  text: 'Playing in WebView',
                ));
              },
              onReceivedError: (controller, request, error) {
                if (request.isForMainFrame != true) return;
                widget.logger?.warning(
                  'Mobile player failed to load',
                  context: {
                    'url': _url,
                    'error': error.description,
                  },
                );
                if (!mounted) return;
                setState(() {
                  _loading = false;
                  _loadError = error.description;
                });
                widget.onStatus?.call(PlaybackStatus(
                  stage: PlaybackStage.preparing,
                  text: 'Player error: ${error.description}',
                ));
              },
            ),
            if (_loading)
              Align(
                alignment: Alignment.topCenter,
                child: LinearProgressIndicator(
                  minHeight: 2,
                  value: _progress > 0 && _progress < 1 ? _progress : null,
                ),
              ),
            if (_loadError != null)
              ColoredBox(
                color: Colors.black.withValues(alpha: 0.88),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 34,
                            color: scheme.error,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'The player could not load',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _loadError!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xFFB9C2CC),
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 18),
                          FilledButton.tonalIcon(
                            onPressed: _reload,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retry'),
                          ),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: () => unawaited(_openExternal()),
                            icon: const Icon(Icons.open_in_browser),
                            label: const Text('Open in browser'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _reload() {
    setState(() {
      _loadError = null;
      _loading = true;
      _progress = 0;
    });
    unawaited(_controller?.reload());
  }

  void _finish() {
    Navigator.of(context).pop(
      const PlaybackResult(outcome: PlaybackOutcome.finished),
    );
  }

  Future<void> _openExternal() async {
    final uri = Uri.tryParse(_episodePageUrl ?? _url);
    if (uri == null) return;
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No browser could open this player.')),
      );
    }
  }
}

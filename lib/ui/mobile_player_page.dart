import 'dart:async';
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

import 'dart:convert';

import 'package:html/parser.dart' as html_parser;

import '../../core/errors/engine_exception.dart';
import '../models.dart';

/// Permanent gateway used by the original Node engine. It redirects to the
/// current live domain, so the mobile app never has to cache a domain.
const String mobileGateway = 'https://animevietsub.info';

/// Absolute URL for an anime's episode page.
Uri mobileAnimePageUrl(
  String animeUrl, {
  String gateway = mobileGateway,
}) {
  final path = _pathOf(animeUrl);
  final normalized =
      path.endsWith('/') ? path.substring(0, path.length - 1) : path;
  final suffix = normalized.isEmpty ? '/' : '$normalized/xem-phim.html';
  return Uri.parse('$gateway$suffix');
}

/// Absolute URL for a single episode, routed through the same gateway.
Uri mobileEpisodePageUrl(
  String episodeUrl, {
  String gateway = mobileGateway,
}) {
  final path = _pathOf(episodeUrl);
  return Uri.parse('$gateway${path.startsWith('/') ? '' : '/'}$path');
}

/// Numeric episode id used by the site's `/ajax/player` endpoint.
String? mobileEpisodeId(String episodeUrl) {
  final path = _pathOf(episodeUrl);
  return RegExp(r'-(\d+)\.html$').firstMatch(path)?.group(1);
}

/// Parse the HTML fragment returned by `POST /ajax/suggest`.
///
/// Mirrors `lib/search.js`: every `li` except `.ss-bottom` is a result, the
/// title and link come from `a.ss-title`, and the poster comes from the
/// background image on `a.thumb`.
List<AnimeSummary> parseMobileSearch(
  String html, {
  required Uri baseUri,
}) {
  final document = html_parser.parse(html);
  final results = <AnimeSummary>[];

  for (final item in document.querySelectorAll('li')) {
    if (item.classes.contains('ss-bottom')) continue;
    final link = item.querySelector('a.ss-title');
    if (link == null) continue;

    final title = link.text.trim();
    final href = link.attributes['href']?.trim() ?? '';
    if (title.isEmpty || href.isEmpty) continue;

    final style = item.querySelector('a.thumb')?.attributes['style'] ?? '';
    results.add(AnimeSummary(
      title: title,
      url: baseUri.resolve(href).toString(),
      poster: _posterFromStyle(style),
    ));
  }

  // An empty list is only valid when the site rendered its "view all" footer.
  // Anything else is a challenge page or a site change, not a real result.
  if (results.isEmpty &&
      document.querySelector('li.ss-bottom #suggest-all') == null) {
    throw EngineException(
      EngineErrorKind.protocol,
      'Unexpected search response: the site may be unavailable or showing a '
      'security challenge. Try again later.',
    );
  }
  return results;
}

/// One page of the site's full search results at `/tim-kiem/<query>/`.
class MobileSearchPage {
  const MobileSearchPage({
    required this.rows,
    required this.pages,
    required this.noResults,
  });

  final List<AnimeSummary> rows;

  /// Total number of pages reported by the pager, at least one.
  final int pages;

  /// True when the site rendered its explicit "no results" message.
  final bool noResults;
}

/// Parse one page of the full search results.
///
/// Mirrors `lib/search.js`: every `li.TPostMv article` is a result, the title
/// comes from `h2.Title` (falling back to `.Title`), the link from the first
/// anchor, and the poster from the first image. `.movie-list-noresult` marks a
/// legitimate empty search; any other empty page is a challenge or a layout
/// change rather than a real result.
MobileSearchPage parseMobileSearchPage(
  String html, {
  required Uri baseUri,
}) {
  final document = html_parser.parse(html);
  final rows = <AnimeSummary>[];

  for (final article in document.querySelectorAll('li.TPostMv article')) {
    final link = article.querySelector('a[href]') ?? article.querySelector('a');
    final href = link?.attributes['href']?.trim() ?? '';
    var title = article.querySelector('h2.Title')?.text.trim() ?? '';
    if (title.isEmpty) {
      title = article.querySelector('.Title')?.text.trim() ?? '';
    }
    if (title.isEmpty || href.isEmpty) continue;

    final poster =
        article.querySelector('img')?.attributes['src']?.trim() ?? '';
    rows.add(AnimeSummary(
      title: title,
      url: baseUri.resolve(href).toString(),
      poster: poster,
    ));
  }

  final noResults = document.querySelector('.movie-list-noresult') != null;
  if (rows.isEmpty && !noResults) {
    throw EngineException(
      EngineErrorKind.protocol,
      'Unexpected search response: the site may be unavailable or showing a '
      'security challenge. Try again later.',
    );
  }

  final pager = document.querySelector('.wp-pagenavi .pages')?.text ?? '';
  final reported = int.tryParse(
    RegExp(r'của\s+(\d+)', caseSensitive: false).firstMatch(pager)?.group(1) ??
        '',
  );
  return MobileSearchPage(
    rows: rows,
    pages: reported != null && reported > 0 ? reported : 1,
    noResults: noResults,
  );
}

/// Convert the rows emitted by the headless WebView into episodes.
List<Episode> parseMobileEpisodes(
  List<Object?> rows, {
  String? preferredEpisodeUrl,
  String? latestEpisode,
}) {
  final preferredPath =
      preferredEpisodeUrl == null || preferredEpisodeUrl.trim().isEmpty
          ? null
          : _pathOf(preferredEpisodeUrl);
  final latest = latestEpisode?.trim().toLowerCase() ?? '';
  var marked = false;
  final episodes = <Episode>[];

  for (final row in rows) {
    if (row is! Map) continue;
    final title = (row['title'] as String? ?? '').trim();
    final name = (row['name'] as String? ?? '').trim();
    final url = (row['url'] as String? ?? '').trim();
    if (url.isEmpty) continue;

    final display = name.isNotEmpty ? name : title;
    if (display.isEmpty) continue;

    var preferred = false;
    if (!marked) {
      if (preferredPath != null) {
        preferred = _pathOf(url) == preferredPath;
      } else if (latest.isNotEmpty) {
        preferred =
            display.toLowerCase() == latest || title.toLowerCase() == latest;
      }
      if (preferred) marked = true;
    }

    episodes.add(Episode(
      title: display,
      url: url,
      originalTitle: display,
      preferred: preferred,
    ));
  }
  return episodes;
}

class MobilePlayerServer {
  const MobilePlayerServer({
    required this.href,
    required this.play,
    required this.id,
    required this.label,
  });

  final String href;
  final String play;
  final String id;
  final String label;
}

/// Server buttons in the backup-server HTML returned by `/ajax/player`.
///
/// Ordered by reliability on mobile networks: the site's API servers (DU/FB)
/// return an embeddable iframe player on a CDN, while the HDX/ADS server
/// resolves to `abyssplayer.com`, which resets connections on some carriers
/// (`net::ERR_CONNECTION_REFUSED`). Callers should try each candidate in turn
/// until one yields a playable link.
List<MobilePlayerServer> parseMobilePlayerServers(String html) {
  final document = html_parser.parse(html);
  final servers = <MobilePlayerServer>[];
  for (final button in document.querySelectorAll('.btn3dsv')) {
    final href = button.attributes['data-href']?.trim() ?? '';
    if (href.isEmpty) continue;
    servers.add(MobilePlayerServer(
      href: href,
      play: button.attributes['data-play'] ?? '',
      id: button.attributes['data-id'] ?? '',
      label: button.text.trim(),
    ));
  }
  servers.sort((a, b) {
    final byKind = _serverRank(a).compareTo(_serverRank(b));
    if (byKind != 0) return byKind;
    final aId = int.tryParse(a.id) ?? 1 << 30;
    final bId = int.tryParse(b.id) ?? 1 << 30;
    return aId.compareTo(bId);
  });
  return servers;
}

int _serverRank(MobilePlayerServer server) => switch (server.play) {
      'api' => 0,
      'embed' => 2,
      _ => 1,
    };

/// Extract the final player URL from the second `/ajax/player` response.
String parseMobilePlayerLink(Object? response) {
  final link = tryParseMobilePlayerLink(response);
  if (link != null) return link;
  throw EngineException(
    EngineErrorKind.protocol,
    'The site did not return a playable stream link.',
  );
}

/// Like [parseMobilePlayerLink], but returns null instead of throwing so the
/// caller can fall back to another server.
String? tryParseMobilePlayerLink(Object? response) {
  Object? decoded = response;
  if (decoded is String) {
    try {
      decoded = jsonDecode(decoded);
    } on FormatException {
      return null;
    }
  }
  if (decoded is Map) {
    final link = decoded['link'];
    if (link is String && link.trim().isNotEmpty) {
      final uri = Uri.tryParse(link.trim());
      if (uri != null &&
          (uri.scheme == 'http' || uri.scheme == 'https') &&
          uri.host.isNotEmpty) {
        return uri.toString();
      }
    }
  }
  return null;
}

/// True when the loaded document is a Cloudflare interstitial rather than the
/// requested page.
bool isMobileChallengePage({
  required String title,
  required String bodyText,
}) {
  final haystack = '$title\n$bodyText'.toLowerCase();
  return haystack.contains('just a moment') ||
      haystack.contains('checking your browser') ||
      haystack.contains('attention required') ||
      haystack.contains('kiểm tra bảo mật') ||
      haystack.contains('cf-browser-verification');
}

String _posterFromStyle(String style) {
  final match = RegExp(
    r'''url\(\s*["']?([^"')]+)["']?\s*\)''',
  ).firstMatch(style);
  return match?.group(1)?.trim() ?? '';
}

String _pathOf(String url) {
  final value = url.trim();
  final uri = Uri.tryParse(value);
  if (uri != null && uri.hasScheme) return uri.path;
  return value.split('?').first.split('#').first;
}

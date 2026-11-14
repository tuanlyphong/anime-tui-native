import 'package:anime_tui_native/core/errors/engine_exception.dart';
import 'package:anime_tui_native/engine/mobile/mobile_parsers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('mobile search parsing', () {
    const html = '''
<ul class="suggest-list">
  <li>
    <a class="thumb" href="/phim/naruto"
       style="background-image: url('https://cdn.test/naruto.jpg')"></a>
    <a class="ss-title" href="/phim/naruto">  Naruto  </a>
  </li>
  <li>
    <a class="thumb" href="https://live.test/phim/one-piece"
       style="background-image:url(&quot;https://cdn.test/op.jpg&quot;)"></a>
    <a class="ss-title" href="https://live.test/phim/one-piece">One Piece</a>
  </li>
  <li class="ss-bottom">
    <a id="suggest-all" href="/tim-kiem/nang-cao.html">View all</a>
  </li>
</ul>
''';

    test('extracts titles, absolute URLs, and poster images', () {
      final results = parseMobileSearch(
        html,
        baseUri: Uri.parse('https://live.test/'),
      );

      expect(results, hasLength(2));
      expect(results.first.title, 'Naruto');
      expect(results.first.url, 'https://live.test/phim/naruto');
      expect(results.first.poster, 'https://cdn.test/naruto.jpg');
      expect(results.last.title, 'One Piece');
      expect(results.last.url, 'https://live.test/phim/one-piece');
      expect(results.last.poster, 'https://cdn.test/op.jpg');
    });

    test('returns an empty list for a legitimate empty result', () {
      final results = parseMobileSearch(
        '<ul><li class="ss-bottom"><a id="suggest-all" href="/x">All</a></li></ul>',
        baseUri: Uri.parse('https://live.test/'),
      );

      expect(results, isEmpty);
    });

    test('rejects a challenge or malformed response', () {
      expect(
        () => parseMobileSearch(
          '<html><body>Just a moment...</body></html>',
          baseUri: Uri.parse('https://live.test/'),
        ),
        throwsA(
          isA<EngineException>().having(
            (error) => error.kind,
            'kind',
            EngineErrorKind.protocol,
          ),
        ),
      );
    });
  });

  group('mobile full-search parsing', () {
    test('extracts rows, posters, and the reported page count', () {
      const html = '''
<ul class="list-movie">
  <li class="TPostMv">
    <article>
      <a href="/phim/naruto">
        <img src="https://cdn.test/naruto.jpg" alt="">
        <h2 class="Title">  Naruto  </h2>
      </a>
    </article>
  </li>
  <li class="TPostMv">
    <article>
      <a href="https://live.test/phim/one-piece">
        <img src="https://cdn.test/op.jpg" alt="">
        <div class="Title">One Piece</div>
      </a>
    </article>
  </li>
</ul>
<div class="wp-pagenavi"><span class="pages">Trang 1 của 7</span></div>
''';

      final page = parseMobileSearchPage(
        html,
        baseUri: Uri.parse('https://live.test/'),
      );

      expect(page.rows, hasLength(2));
      expect(page.rows.first.title, 'Naruto');
      expect(page.rows.first.url, 'https://live.test/phim/naruto');
      expect(page.rows.first.poster, 'https://cdn.test/naruto.jpg');
      expect(page.rows.last.title, 'One Piece');
      expect(page.rows.last.url, 'https://live.test/phim/one-piece');
      expect(page.rows.last.poster, 'https://cdn.test/op.jpg');
      expect(page.pages, 7);
      expect(page.noResults, isFalse);
    });

    test('accepts the explicit no-results message as a valid empty page', () {
      final page = parseMobileSearchPage(
        '''
<div class="movie-list-noresult">Không tìm thấy phim phù hợp.</div>
<div class="wp-pagenavi"><span class="pages">Trang 1 của 1</span></div>
''',
        baseUri: Uri.parse('https://live.test/'),
      );

      expect(page.rows, isEmpty);
      expect(page.pages, 1);
      expect(page.noResults, isTrue);
    });

    test('rejects a challenge or malformed page', () {
      expect(
        () => parseMobileSearchPage(
          '<html><body>Just a moment...</body></html>',
          baseUri: Uri.parse('https://live.test/'),
        ),
        throwsA(
          isA<EngineException>().having(
            (error) => error.kind,
            'kind',
            EngineErrorKind.protocol,
          ),
        ),
      );
    });
  });

  group('mobile episode parsing', () {
    test('uses the anchor name, keeps original titles, and marks the latest',
        () {
      final episodes = parseMobileEpisodes(
        <Object?>[
          <String, Object?>{
            'title': 'Tập 2',
            'name': 'Tập 2',
            'url': 'https://live.test/phim/naruto/tap-2-222.html',
          },
          <String, Object?>{
            'title': 'Tập 1',
            'name': 'Tập 1',
            'url': 'https://live.test/phim/naruto/tap-1-111.html',
          },
          <String, Object?>{
            'title': 'Trailer',
            'name': '',
            'url': 'https://live.test/phim/naruto/trailer-1.html',
          },
        ],
        latestEpisode: 'Tập 1',
      );

      expect(episodes, hasLength(3));
      expect(episodes.first.originalTitle, 'Tập 2');
      expect(episodes[1].preferred, isTrue);
      expect(episodes[1].hasProgress, isTrue);
      expect(episodes.first.preferred, isFalse);
      expect(episodes.last.title, 'Trailer');
      expect(episodes.last.url, 'https://live.test/phim/naruto/trailer-1.html');
    });

    test('an explicit preferred URL wins over the history title', () {
      final episodes = parseMobileEpisodes(
        <Object?>[
          <String, Object?>{
            'title': 'Tập 1',
            'name': 'Tập 1',
            'url': 'https://live.test/phim/naruto/tap-1-111.html',
          },
          <String, Object?>{
            'title': 'Tập 2',
            'name': 'Tập 2',
            'url': 'https://live.test/phim/naruto/tap-2-222.html',
          },
        ],
        latestEpisode: 'Tập 1',
        preferredEpisodeUrl: 'https://live.test/phim/naruto/tap-2-222.html',
      );

      expect(episodes.first.preferred, isFalse);
      expect(episodes.last.preferred, isTrue);
    });

    test('ignores malformed rows', () {
      final episodes = parseMobileEpisodes(
        <Object?>[
          'not a map',
          <String, Object?>{'title': 'No URL'},
          <String, Object?>{'url': 'https://live.test/episode.html'},
        ],
      );

      expect(episodes, isEmpty);
    });
  });

  group('mobile URLs', () {
    test('routes anime pages through the permanent gateway', () {
      expect(
        mobileAnimePageUrl('https://live.test/phim/naruto').toString(),
        'https://animevietsub.info/phim/naruto/xem-phim.html',
      );
      expect(
        mobileAnimePageUrl('https://live.test/phim/naruto/').toString(),
        'https://animevietsub.info/phim/naruto/xem-phim.html',
      );
    });

    test('routes episode pages through the gateway with the same path', () {
      expect(
        mobileEpisodePageUrl(
          'https://live.test/phim/naruto/tap-1-111.html',
        ).toString(),
        'https://animevietsub.info/phim/naruto/tap-1-111.html',
      );
      expect(
        mobileEpisodeId(
          'https://live.test/phim/naruto/tap-1-111.html',
        ),
        '111',
      );
      expect(
        mobileEpisodeId('https://live.test/phim/naruto/xem-phim.html'),
        isNull,
      );
    });
  });

  group('mobile player handshake', () {
    test('orders API servers before the HDX embed server', () {
      const html = '''
<div class="server">
  <a class="btn3dsv" data-href="hdx-token" data-play="embed" data-id="3">
    HDX(ADS)
  </a>
</div>
<div class="server">
  <a class="btn3dsv" data-href="fb-token" data-play="api" data-id="2">FB</a>
</div>
<div class="server">
  <a class="btn3dsv" data-href="du-token" data-play="api" data-id="0">DU</a>
</div>
''';

      final servers = parseMobilePlayerServers(html);

      expect(servers, hasLength(3));
      expect(servers.map((server) => server.label),
          <String>['DU', 'FB', 'HDX(ADS)']);
      expect(servers.first.href, 'du-token');
      expect(servers.first.play, 'api');
      expect(servers.first.id, '0');
    });

    test('ignores backup entries without a server token', () {
      expect(
        parseMobilePlayerServers(
          '<a class="btn3dsv" data-play="api" data-id="0">Empty</a>',
        ),
        isEmpty,
      );
    });

    test('extracts the final player link', () {
      expect(
        parseMobilePlayerLink(<String, Object?>{
          'link': 'https://stream.example.com/player/abc',
        }),
        'https://stream.example.com/player/abc',
      );

      expect(
        tryParseMobilePlayerLink(<String, Object?>{'success': false}),
        isNull,
      );
      expect(
        () => parseMobilePlayerLink(<String, Object?>{'success': false}),
        throwsA(
          isA<EngineException>().having(
            (error) => error.kind,
            'kind',
            EngineErrorKind.protocol,
          ),
        ),
      );
    });

    test('detects a Cloudflare challenge page', () {
      expect(
        isMobileChallengePage(
          title: 'Just a moment...',
          bodyText: 'Checking your browser',
        ),
        isTrue,
      );
      expect(
        isMobileChallengePage(
          title: 'Naruto - Anime Vietsub',
          bodyText: 'Danh sách tập',
        ),
        isFalse,
      );
    });
  });
}

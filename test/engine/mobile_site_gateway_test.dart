import 'package:anime_tui_native/core/errors/engine_exception.dart';
import 'package:anime_tui_native/engine/mobile/mobile_site_gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const String _suggestHtml = '''
<li>
  <a class="thumb" href="/phim/naruto" style="background-image:url(https://cdn.test/naruto.jpg)"></a>
  <a class="ss-title" href="/phim/naruto">Naruto</a>
</li>
<li class="ss-bottom"><a id="suggest-all" href="/all">All</a></li>
''';

const String _emptySuggestHtml =
    '<li class="ss-bottom"><a id="suggest-all" href="/all">All</a></li>';

const String _noResultsHtml = '''
<div class="movie-list-noresult">Không tìm thấy phim phù hợp.</div>
<div class="wp-pagenavi"><span class="pages">Trang 1 của 1</span></div>
''';

http.Response _html(String body) => http.Response(
      body,
      200,
      headers: <String, String>{
        'content-type': 'text/html; charset=utf-8',
      },
    );

String _searchPageHtml({
  int page = 1,
  int pages = 1,
  List<String> titles = const <String>['Naruto', 'Boruto'],
}) {
  final rows = titles.map((title) {
    final slug = title.toLowerCase().replaceAll(' ', '-');
    return '''
  <li class="TPostMv">
    <article>
      <a href="/phim/$slug">
        <img src="https://cdn.test/$slug.jpg" alt="">
        <h2 class="Title">$title</h2>
      </a>
    </article>
  </li>''';
  }).join();
  return '''
<ul class="list-movie">$rows
</ul>
<div class="wp-pagenavi"><span class="pages">Trang $page của $pages</span></div>
''';
}

void main() {
  test('merges suggest results with the full search page and deduplicates',
      () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.url.path == '/ajax/suggest') {
        return _html(_suggestHtml);
      }
      return _html(_searchPageHtml());
    });
    final gateway = MobileSiteGateway(
      client: client,
      originResolver: () async => Uri.parse('https://live.test/'),
    );

    final results = await gateway.search('naruto');

    final suggest =
        requests.singleWhere((request) => request.url.path == '/ajax/suggest');
    expect(suggest.method, 'POST');
    expect(suggest.url.toString(), 'https://live.test/ajax/suggest');
    expect(suggest.headers['Content-Type'],
        contains('application/x-www-form-urlencoded'));
    expect(suggest.bodyFields, <String, String>{
      'ajaxSearch': '1',
      'keysearch': 'naruto',
    });

    final page = requests.singleWhere(
      (request) => request.url.path.startsWith('/tim-kiem/'),
    );
    expect(page.method, 'GET');
    expect(page.url.toString(), 'https://live.test/tim-kiem/naruto/');

    expect(results, hasLength(2));
    expect(results.map((result) => result.title), <String>[
      'Naruto',
      'Boruto',
    ]);
    expect(results.first.url, 'https://live.test/phim/naruto');
  });

  test('follows the gateway redirect before searching', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.url.host == 'gateway.test') {
        return http.Response('', 301, headers: <String, String>{
          'location': 'https://live.test/',
        });
      }
      if (request.url.path == '/ajax/suggest') {
        return _html(_suggestHtml);
      }
      return _html(_searchPageHtml(titles: <String>['Naruto']));
    });
    final gateway = MobileSiteGateway(
      client: client,
      gateway: Uri.parse('https://gateway.test/'),
    );

    final results = await gateway.search('naruto');

    expect(
      requests.where((request) => request.url.host == 'gateway.test'),
      hasLength(2),
    );
    expect(
      requests.where((request) => request.url.host == 'live.test'),
      hasLength(2),
    );
    expect(
      requests.every((request) => request.followRedirects == false),
      isTrue,
    );
    expect(
      requests
          .singleWhere((request) =>
              request.url.host == 'live.test' &&
              request.url.path == '/ajax/suggest')
          .url
          .toString(),
      'https://live.test/ajax/suggest',
    );
    expect(results.single.url, 'https://live.test/phim/naruto');
  });

  test('caps full search pages at maxSearchPages', () async {
    final requested = <String>[];
    final client = MockClient((request) async {
      if (request.url.path == '/ajax/suggest') {
        return _html(_emptySuggestHtml);
      }
      requested.add(request.url.toString());
      final match = RegExp(r'trang-(\d+)\.html$').firstMatch(request.url.path);
      final page = int.parse(match?.group(1) ?? '1');
      return _html(
        _searchPageHtml(page: page, pages: 10, titles: <String>['Title $page']),
      );
    });
    final gateway = MobileSiteGateway(
      client: client,
      originResolver: () async => Uri.parse('https://live.test/'),
      maxSearchPages: 2,
    );

    final results = await gateway.search('one piece');

    expect(requested, hasLength(2));
    expect(requested.first, 'https://live.test/tim-kiem/one%20piece/');
    expect(
        requested.last, 'https://live.test/tim-kiem/one%20piece/trang-2.html');
    expect(requested.any((url) => url.contains('trang-3.html')), isFalse);
    expect(results.map((result) => result.title), <String>[
      'Title 1',
      'Title 2',
    ]);
  });

  test('returns an empty list when the site reports no matches', () async {
    final client = MockClient((request) async {
      if (request.url.path == '/ajax/suggest') {
        return _html(_emptySuggestHtml);
      }
      return _html(_noResultsHtml);
    });
    final gateway = MobileSiteGateway(
      client: client,
      originResolver: () async => Uri.parse('https://live.test/'),
    );

    expect(await gateway.search('nothing'), isEmpty);
  });

  test('keeps page results when the suggest endpoint fails', () async {
    final client = MockClient((request) async {
      if (request.url.path == '/ajax/suggest') {
        return http.Response('blocked', 500);
      }
      return _html(_searchPageHtml(titles: <String>['Naruto']));
    });
    final gateway = MobileSiteGateway(
      client: client,
      originResolver: () async => Uri.parse('https://live.test/'),
    );

    final results = await gateway.search('naruto');

    expect(results.single.title, 'Naruto');
  });

  test('retries a cookieless challenge with the session cookie', () async {
    var attempts = 0;
    final cookieHeaders = <String?>[];
    final client = MockClient((request) async {
      if (request.url.path == '/ajax/suggest') {
        attempts++;
        cookieHeaders.add(request.headers['Cookie']);
        if (attempts == 1) {
          return http.Response(
            "<script>window.location='/challenge';</script>",
            403,
            headers: <String, String>{
              'set-cookie': 'session=abc; Path=/; HttpOnly',
            },
          );
        }
        return _html(_suggestHtml);
      }
      return _html(_noResultsHtml);
    });
    final gateway = MobileSiteGateway(
      client: client,
      originResolver: () async => Uri.parse('https://live.test/'),
    );

    final results = await gateway.search('naruto');

    expect(attempts, 2);
    expect(cookieHeaders.first, isNull);
    expect(cookieHeaders.last, contains('session=abc'));
    expect(results.single.title, 'Naruto');
  });

  test('maps HTTP failures to a network error', () async {
    final gateway = MobileSiteGateway(
      client: MockClient((request) async => http.Response('blocked', 403)),
      originResolver: () async => Uri.parse('https://live.test/'),
    );

    await expectLater(
      gateway.search('naruto'),
      throwsA(
        isA<EngineException>().having(
          (error) => error.kind,
          'kind',
          EngineErrorKind.network,
        ),
      ),
    );
  });
}

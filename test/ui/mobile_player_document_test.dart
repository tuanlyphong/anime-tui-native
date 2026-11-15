import 'package:anime_tui_native/ui/mobile_player_page.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('mobile player wrapper', () {
    test('embeds the stream in an iframe instead of opening it top-level', () {
      final html = buildMobilePlayerDocument(
        'https://stream.example.com/player/abc',
      );

      expect(html, contains('<iframe'));
      expect(
        html,
        contains('src="https://stream.example.com/player/abc"'),
      );
      expect(html, contains('allowfullscreen'));
      expect(html, contains('autoplay'));
    });

    test('escapes query separators in the iframe URL', () {
      final html = buildMobilePlayerDocument(
        'https://stream.example.com/player?one=1&two=2',
      );

      expect(
        html,
        contains('src="https://stream.example.com/player?one=1&amp;two=2"'),
      );
    });
  });

  group('mobile player ad blocking', () {
    test('strips pause ads and removes their overlay nodes', () {
      final script = buildMobilePlayerAdBlockScript();

      expect(script, contains('pauseAd'));
      expect(script, contains('adqc.net'));
      expect(script, contains('MutationObserver'));
    });

    test('runs in every frame before the player builds the overlay', () {
      final scripts = buildMobilePlayerUserScripts();

      expect(scripts, hasLength(1));
      expect(scripts.single.injectionTime,
          UserScriptInjectionTime.AT_DOCUMENT_START);
      expect(scripts.single.forMainFrameOnly, isFalse);
      expect(scripts.single.source, contains('pauseAd'));
    });
  });
}

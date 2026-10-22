import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_omniverse/screens/notifications_screen.dart';

void main() {
  group('splitLeadingMentions', () {
    test('先頭の @ID を本文から分ける', () {
      final r = splitLeadingMentions('@me @friend ありがとう！');
      expect(r.mentions, ['@me', '@friend']);
      expect(r.rest, 'ありがとう！');
    });

    test('Bluesky のドット入り ID も分ける', () {
      final r = splitLeadingMentions('@me.bsky.social おつかれ');
      expect(r.mentions, ['@me.bsky.social']);
      expect(r.rest, 'おつかれ');
    });

    test('途中の @ID はそのまま残す', () {
      final r = splitLeadingMentions('こんにちは @me さん');
      expect(r.mentions, isEmpty);
      expect(r.rest, 'こんにちは @me さん');
    });

    test('@ID だけの本文は、本文が空になる', () {
      final r = splitLeadingMentions('@me ');
      expect(r.mentions, ['@me']);
      expect(r.rest, isEmpty);
    });
  });
}

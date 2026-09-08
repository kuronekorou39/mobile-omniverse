import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_omniverse/services/shadowban_check_service.dart';

void main() {
  ShadowbanFinding find(Map<String, dynamic> result, String label) =>
      ShadowbanCheckService.analyze(result)
          .firstWhere((f) => f.label == label);

  /// フラグが何も立っていない、ふつうのアカウント
  Map<String, dynamic> cleanResult() => {
        'rest_id': '111',
        'has_graduated_access': true,
        'privacy': {'protected': false},
        'relationship_perspectives': {'blocked_by': false},
        'legacy': {
          'possibly_sensitive': false,
          'profile_interstitial_type': '',
          'needs_phone_verification': false,
          'withheld_scope': '',
          'withheld_in_countries': <String>[],
        },
      };

  group('analyze — フラグ無し', () {
    test('すべて notFlagged になる', () {
      final findings = ShadowbanCheckService.analyze(cleanResult());

      expect(findings, isNotEmpty);
      expect(
        findings.where((f) => f.verdict != ShadowbanVerdict.notFlagged),
        isEmpty,
      );
    });
  });

  group('analyze — 個別のフラグ', () {
    test('possibly_sensitive が true なら flagged', () {
      final result = cleanResult();
      (result['legacy'] as Map)['possibly_sensitive'] = true;

      expect(find(result, 'アカウント単位のセンシティブ判定').verdict,
          ShadowbanVerdict.flagged);
    });

    test('profile_interstitial_type が sensitive_media なら flagged', () {
      final result = cleanResult();
      (result['legacy'] as Map)['profile_interstitial_type'] = 'sensitive_media';

      expect(find(result, 'プロフィール画像のセンシティブ判定').verdict,
          ShadowbanVerdict.flagged);
    });

    test('見たことのない interstitial の値は unknown に倒す', () {
      final result = cleanResult();
      (result['legacy'] as Map)['profile_interstitial_type'] = 'something_new';

      final finding = find(result, 'プロフィール画像のセンシティブ判定');
      expect(finding.verdict, ShadowbanVerdict.unknown);
      expect(finding.detail, contains('something_new'));
    });

    test('has_graduated_access が false なら flagged', () {
      final result = cleanResult();
      result['has_graduated_access'] = false;

      expect(find(result, 'アカウントの評価待ち').verdict, ShadowbanVerdict.flagged);
    });

    test('鍵アカウントは flagged', () {
      final result = cleanResult();
      (result['privacy'] as Map)['protected'] = true;

      expect(find(result, '鍵アカウント').verdict, ShadowbanVerdict.flagged);
    });

    test('withheld_in_countries に国が入っていれば flagged で国名が出る', () {
      final result = cleanResult();
      (result['legacy'] as Map)['withheld_in_countries'] = ['DE', 'FR'];

      final finding = find(result, '国別の表示制限');
      expect(finding.verdict, ShadowbanVerdict.flagged);
      expect(finding.detail, contains('DE'));
      expect(finding.detail, contains('FR'));
    });

    test('blocked_by は relationship_perspectives から読む', () {
      final result = cleanResult();
      (result['relationship_perspectives'] as Map)['blocked_by'] = true;

      expect(find(result, '検査アカウントからブロックされている').verdict,
          ShadowbanVerdict.flagged);
    });
  });

  group('analyze — 項目が欠けているとき', () {
    test('返ってこない項目は notFlagged ではなく unknown', () {
      final findings = ShadowbanCheckService.analyze({'rest_id': '111'});

      expect(findings, isNotEmpty);
      expect(
        findings.where((f) => f.verdict == ShadowbanVerdict.notFlagged),
        isEmpty,
        reason: '項目が無いことを「シロ」にしてはいけない',
      );
    });

    test('legacy が空でも落ちない', () {
      final findings = ShadowbanCheckService.analyze({'legacy': {}});
      expect(findings, isNotEmpty);
    });

    test('型が違っても落ちない', () {
      final findings = ShadowbanCheckService.analyze({
        'legacy': 'not a map',
        'has_graduated_access': 'yes',
        'privacy': 42,
      });
      expect(findings, isNotEmpty);
      expect(
        findings.where((f) => f.verdict == ShadowbanVerdict.flagged),
        isEmpty,
      );
    });
  });

  group('ShadowbanReport', () {
    ShadowbanReport report({
      required String screenName,
      required String by,
      List<ShadowbanFinding> findings = const [],
    }) =>
        ShadowbanReport(
          screenName: screenName,
          checkedAt: DateTime(2026, 9, 9),
          checkedByHandle: by,
          findings: findings,
        );

    test('自分で自分を検査していることを見分ける', () {
      expect(report(screenName: 'alice', by: 'alice').isSelfCheck, isTrue);
      expect(report(screenName: 'Alice', by: 'alice').isSelfCheck, isTrue);
      expect(report(screenName: 'bob', by: 'alice').isSelfCheck, isFalse);
    });

    test('flagged だけを拾える', () {
      final r = report(
        screenName: 'bob',
        by: 'alice',
        findings: const [
          ShadowbanFinding(
              label: 'A', verdict: ShadowbanVerdict.flagged, detail: ''),
          ShadowbanFinding(
              label: 'B', verdict: ShadowbanVerdict.notFlagged, detail: ''),
          ShadowbanFinding(
              label: 'C', verdict: ShadowbanVerdict.unknown, detail: ''),
        ],
      );

      expect(r.anyFlagged, isTrue);
      expect(r.flagged.single.label, 'A');
    });

    test('フラグが無ければ anyFlagged は false', () {
      final r = report(
        screenName: 'bob',
        by: 'alice',
        findings: const [
          ShadowbanFinding(
              label: 'A', verdict: ShadowbanVerdict.notFlagged, detail: ''),
        ],
      );
      expect(r.anyFlagged, isFalse);
    });
  });
}

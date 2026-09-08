import '../models/account.dart';
import 'x_api_service.dart';

/// 検査項目ひとつの結論
enum ShadowbanVerdict {
  /// 制限を示すフラグが立っている
  flagged,

  /// フラグは立っていない。**「制限されていない」ではない**
  notFlagged,

  /// 判定できなかった（項目が返らない・取得に失敗した など）
  unknown,
}

/// 検査項目ひとつ
class ShadowbanFinding {
  const ShadowbanFinding({
    required this.label,
    required this.verdict,
    required this.detail,
  });

  final String label;
  final ShadowbanVerdict verdict;

  /// その結論になった理由。フラグ名をそのまま書いてよい
  final String detail;
}

/// 診断結果
class ShadowbanReport {
  const ShadowbanReport({
    required this.screenName,
    required this.checkedAt,
    required this.checkedByHandle,
    required this.findings,
    this.error,
  });

  final String screenName;
  final DateTime checkedAt;

  /// どのアカウントの資格情報で見に行ったか。本人バイアスの判断に要る
  final String checkedByHandle;

  final List<ShadowbanFinding> findings;

  /// 取得そのものに失敗したときのメッセージ
  final String? error;

  bool get hasError => error != null;

  List<ShadowbanFinding> get flagged =>
      findings.where((f) => f.verdict == ShadowbanVerdict.flagged).toList();

  bool get anyFlagged => flagged.isNotEmpty;

  /// 自分の資格情報で自分を見ている状態。
  ///
  /// X の可視性フィルタは著者本人には適用されない作りなので、
  /// この場合「出ている」ことに意味がない
  bool get isSelfCheck =>
      checkedByHandle.toLowerCase() == screenName.toLowerCase();
}

/// X のアカウントに「表示されにくくなるフラグ」が付いていないかを見る。
///
/// できるのは **症状の有無を見ること** だけで、シャドウバンの有無を
/// 判定するものではない。フラグが無いことは「制限されていない」ことを
/// 意味しない (X 側には Downrank のように外から観測できない措置がある)。
///
/// いまは UserByScreenName 1 回で取れるプロフィールのフラグだけを見る。
/// 検索や会話ツリーを使う判定 (サーチバン・ゴーストバン・リプライ
/// デブースティング) は別のオペレーションが要るため、まだ扱わない。
class ShadowbanCheckService {
  ShadowbanCheckService._();
  static final instance = ShadowbanCheckService._();

  XApiService xApi = XApiService.instance;

  Future<ShadowbanReport> check(Account by, String screenName) async {
    final target = screenName.replaceFirst(RegExp(r'^@+'), '').trim();

    Map<String, dynamic>? result;
    try {
      result = await xApi.getUserResult(by.xCredentials, target);
    } catch (e) {
      return ShadowbanReport(
        screenName: target,
        checkedAt: DateTime.now(),
        checkedByHandle: _bareHandle(by.handle),
        findings: const [],
        error: '$e',
      );
    }

    if (result == null) {
      return ShadowbanReport(
        screenName: target,
        checkedAt: DateTime.now(),
        checkedByHandle: _bareHandle(by.handle),
        findings: const [],
        error: 'アカウントが見つかりません（ID 違い・凍結・削除のいずれか）',
      );
    }

    return ShadowbanReport(
      screenName: target,
      checkedAt: DateTime.now(),
      checkedByHandle: _bareHandle(by.handle),
      findings: analyze(result),
    );
  }

  static String _bareHandle(String handle) =>
      handle.replaceFirst(RegExp(r'^@+'), '');

  /// UserByScreenName の生 result からフラグを読む
  static List<ShadowbanFinding> analyze(Map<String, dynamic> result) {
    final legacy = _map(result['legacy']);
    final privacy = _map(result['privacy']);
    final perspectives = _map(result['relationship_perspectives']);

    return [
      _boolFinding(
        label: 'アカウント単位のセンシティブ判定',
        value: legacy['possibly_sensitive'],
        whenTrue: 'possibly_sensitive が true。検索結果から外れることが多い',
        whenFalse: 'possibly_sensitive は false',
      ),
      _interstitialFinding(legacy['profile_interstitial_type']),
      _graduatedFinding(result['has_graduated_access']),
      _boolFinding(
        label: '鍵アカウント',
        value: privacy['protected'] ?? legacy['protected'],
        whenTrue: '非公開。そもそも他人からは見えない',
        whenFalse: '公開アカウント',
      ),
      _withheldFinding(legacy),
      _boolFinding(
        label: '電話番号の確認待ち',
        value: legacy['needs_phone_verification'],
        whenTrue: 'needs_phone_verification が true。確認が済むまで制限される',
        whenFalse: 'needs_phone_verification は false',
      ),
      _boolFinding(
        label: '検査アカウントからブロックされている',
        value: perspectives['blocked_by'] ?? legacy['blocked_by'],
        whenTrue: 'blocked_by が true。この関係だと他の判定も歪む',
        whenFalse: 'ブロックされていない',
      ),
    ];
  }

  static ShadowbanFinding _boolFinding({
    required String label,
    required Object? value,
    required String whenTrue,
    required String whenFalse,
  }) {
    if (value is! bool) {
      return ShadowbanFinding(
        label: label,
        verdict: ShadowbanVerdict.unknown,
        detail: '項目が返ってきませんでした',
      );
    }
    return ShadowbanFinding(
      label: label,
      verdict: value ? ShadowbanVerdict.flagged : ShadowbanVerdict.notFlagged,
      detail: value ? whenTrue : whenFalse,
    );
  }

  /// アイコン・ヘッダー画像がセンシティブ扱いされているか
  static ShadowbanFinding _interstitialFinding(Object? value) {
    const label = 'プロフィール画像のセンシティブ判定';
    if (value is! String) {
      return const ShadowbanFinding(
        label: label,
        verdict: ShadowbanVerdict.unknown,
        detail: '項目が返ってきませんでした',
      );
    }
    if (value.isEmpty) {
      return const ShadowbanFinding(
        label: label,
        verdict: ShadowbanVerdict.notFlagged,
        detail: 'profile_interstitial_type は空',
      );
    }
    const flaggedTypes = {'sensitive_media', 'offensive_profile_content'};
    return ShadowbanFinding(
      label: label,
      verdict: flaggedTypes.contains(value)
          ? ShadowbanVerdict.flagged
          : ShadowbanVerdict.unknown,
      detail: 'profile_interstitial_type = $value',
    );
  }

  /// 新規・未評価アカウントのリーチ制限
  static ShadowbanFinding _graduatedFinding(Object? value) {
    const label = 'アカウントの評価待ち';
    if (value is! bool) {
      return const ShadowbanFinding(
        label: label,
        verdict: ShadowbanVerdict.unknown,
        detail: '項目が返ってきませんでした',
      );
    }
    return ShadowbanFinding(
      label: label,
      verdict: value ? ShadowbanVerdict.notFlagged : ShadowbanVerdict.flagged,
      detail: value
          ? 'has_graduated_access は true'
          : 'has_graduated_access が false。'
              '真正性の評価中でリーチが絞られている状態',
    );
  }

  /// 国別の表示制限
  static ShadowbanFinding _withheldFinding(Map<String, dynamic> legacy) {
    const label = '国別の表示制限';
    final scope = legacy['withheld_scope'];
    final description = legacy['withheld_description'];
    final countries = legacy['withheld_in_countries'];

    final hasScope = scope is String && scope.isNotEmpty;
    final hasCountries = countries is List && countries.isNotEmpty;

    if (!legacy.containsKey('withheld_scope') &&
        !legacy.containsKey('withheld_in_countries')) {
      return const ShadowbanFinding(
        label: label,
        verdict: ShadowbanVerdict.unknown,
        detail: '項目が返ってきませんでした',
      );
    }
    if (!hasScope && !hasCountries) {
      return const ShadowbanFinding(
        label: label,
        verdict: ShadowbanVerdict.notFlagged,
        detail: '制限されている国はありません',
      );
    }
    final where = hasCountries ? (countries).join(', ') : '$scope';
    return ShadowbanFinding(
      label: label,
      verdict: ShadowbanVerdict.flagged,
      detail: description is String && description.isNotEmpty
          ? '$where ($description)'
          : where,
    );
  }

  static Map<String, dynamic> _map(Object? value) =>
      value is Map<String, dynamic> ? value : const {};
}

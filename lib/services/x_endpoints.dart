/// X API のエンドポイント URL を一元管理
class XEndpoints {
  XEndpoints._();

  /// 通知バッジ数
  static const badgeCount =
      'https://x.com/i/api/2/badge_count/badge_count.json?supports_ntab_urt=1';

  /// REST 通知一覧
  static const notificationsAll = '/i/api/2/notifications/all.json';

  /// GraphQL ベース URL
  static const graphqlBase = 'https://x.com/i/api/graphql';

  /// JSバンドル取得用
  static const home = 'https://x.com/home';
}

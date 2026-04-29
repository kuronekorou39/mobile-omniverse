import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/account.dart';
import '../utils/app_snackbar.dart';
import '../models/activity_log.dart';
import '../models/notification_item.dart';
import '../models/post.dart';
import '../models/sns_service.dart';
import '../providers/account_provider.dart';
import '../providers/activity_log_provider.dart';
import '../providers/fetch_status_provider.dart';
import '../providers/notification_badge_provider.dart';
import '../providers/notification_fetch_status_provider.dart';
import '../providers/notification_highlight_provider.dart';
import '../services/bluesky_api_service.dart';
import '../services/notification_cache_service.dart';
import '../services/x_api_service.dart';
import '../widgets/empty_state.dart';
import '../widgets/sns_badge.dart';
import 'notification_webview_screen.dart';
import 'post_detail_screen.dart';
import 'settings_screen.dart';
import 'user_profile_screen.dart';

// ─── 通知取得の共通ロジック ───

/// アカウントの通知を取得し、マージ・重複排除済みのリストを返す
class _NotificationFetchResult {
  const _NotificationFetchResult({
    required this.notifications,
    this.cursor,
    this.responseSnippet,
    this.updatedCreds,
    this.gqlOk = true,
  });
  final List<NotificationItem> notifications;
  final String? cursor;
  final String? responseSnippet;
  /// GraphQL通知（リプライ/メンション）の取得が成功したか
  final bool gqlOk;
  /// Bluesky のトークン更新があった場合
  final SnsCredentials? updatedCreds;
}

Future<_NotificationFetchResult> fetchAccountNotifications(
  Account account, {
  String? cursor,
}) async {
  if (account.service == SnsService.x) {
    if (cursor != null) {
      // ページネーション: REST のみ
      final result = await XApiService.instance
          .getNotifications(account.xCredentials, cursor: cursor);
      return _NotificationFetchResult(
        notifications: result.notifications,
        cursor: result.cursor,
        responseSnippet: result.responseSnippet,
      );
    }
    // 初回/リフレッシュ: REST + GraphQL を並列取得
    final results = await Future.wait([
      XApiService.instance.getNotifications(account.xCredentials),
      XApiService.instance.getNotificationsGraphQL(
        account.xCredentials,
        accountId: account.id,
      ),
    ]);
    final notifResult = results[0]
        as ({List<NotificationItem> notifications, String? cursor, String? responseSnippet});
    final gqlResult = results[1] as ({List<NotificationItem> notifications, bool ok});

    // REST を優先し、GraphQL の重複を排除（IDが異なるため targetPostId でも比較）
    final restPostIds = <String>{
      for (final n in notifResult.notifications)
        if (n.targetPostId != null) n.targetPostId!,
    };
    final dedupedGql = gqlResult.notifications.where((n) =>
        n.targetPostId == null || !restPostIds.contains(n.targetPostId)).toList();
    final merged = [...notifResult.notifications, ...dedupedGql];
    final seen = <String>{};
    merged.retainWhere((n) => seen.add(n.id));
    merged.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return _NotificationFetchResult(
      notifications: merged,
      cursor: notifResult.cursor,
      responseSnippet: notifResult.responseSnippet,
      gqlOk: gqlResult.ok,
    );
  } else {
    // Bluesky
    final result = await BlueskyApiService.instance
        .getNotificationsWithRefresh(account.blueskyCredentials, cursor: cursor);
    return _NotificationFetchResult(
      notifications: result.notifications,
      cursor: result.cursor,
      updatedCreds: result.updatedCreds,
    );
  }
}

// ─── 通知タイプの共通定義 ───

const _typeOrder = [
  NotificationType.like,
  NotificationType.repost,
  NotificationType.reply,
  NotificationType.mention,
  NotificationType.quote,
  NotificationType.follow,
  NotificationType.unknown,
];

IconData _typeIcon(NotificationType type) => switch (type) {
      NotificationType.like => Icons.favorite,
      NotificationType.repost => Icons.repeat,
      NotificationType.reply => Icons.reply,
      NotificationType.mention => Icons.alternate_email,
      NotificationType.quote => Icons.format_quote,
      NotificationType.follow => Icons.person_add,
      NotificationType.unknown => Icons.notifications,
    };

Color _typeColor(NotificationType type) => switch (type) {
      NotificationType.like => Colors.pink,
      NotificationType.repost => Colors.green,
      NotificationType.reply => Colors.blue,
      NotificationType.follow => Colors.purple,
      NotificationType.mention => Colors.orange,
      NotificationType.quote => Colors.teal,
      NotificationType.unknown => Colors.grey,
    };

String _typeLabel(NotificationType type) => switch (type) {
      NotificationType.like => 'いいね',
      NotificationType.repost => 'リポスト',
      NotificationType.reply => 'リプライ',
      NotificationType.mention => 'メンション',
      NotificationType.quote => '引用',
      NotificationType.follow => 'フォロー',
      NotificationType.unknown => 'その他',
    };

/// 通知タイプフィルタ行（共通ウィジェット）
/// [hiddenTypes] に含まれるタイプは非表示。空=全表示。
class _NotificationTypeFilter extends StatelessWidget {
  const _NotificationTypeFilter({
    required this.availableTypes,
    required this.hiddenTypes,
    required this.onToggle,
    required this.onToggleAll,
  });

  final List<NotificationType> availableTypes;
  final Set<NotificationType> hiddenTypes;
  final void Function(NotificationType type) onToggle;
  final void Function(bool showAll) onToggleAll;

  @override
  Widget build(BuildContext context) {
    if (availableTypes.length <= 1) return const SizedBox.shrink();

    final allVisible = hiddenTypes.isEmpty;

    return SizedBox(
      height: 44,
      child: Row(
        children: [
          // 全ON/OFF ボタン（通知タイルのテキスト開始位置に揃える）
          Padding(
            padding: const EdgeInsets.only(left: 76),
            child: InkWell(
              onTap: () => onToggleAll(!allVisible),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Icon(
                  allVisible ? Icons.visibility : Icons.visibility_off,
                  size: 18,
                  color: allVisible ? Theme.of(context).colorScheme.primary : Colors.grey[400],
                ),
              ),
            ),
          ),
          Container(
            width: 1, height: 20, color: Colors.grey.withValues(alpha: 0.2),
            margin: const EdgeInsets.symmetric(horizontal: 4),
          ),
          // タイプ別アイコン
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              children: availableTypes.map((type) {
                final isVisible = !hiddenTypes.contains(type);
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: InkWell(
                    onTap: () => onToggle(type),
                    borderRadius: BorderRadius.circular(12),
                    child: Tooltip(
                      message: _typeLabel(type),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                        child: Icon(
                          _typeIcon(type),
                          size: 20,
                          color: isVisible ? _typeColor(type) : Colors.grey[400]?.withValues(alpha: 0.4),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  /// 0 = 「すべて」、1〜N = 各アカウント（accounts と同じ並び）
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountProvider).where((a) => a.isEnabled).toList();
    final badge = ref.watch(notificationBadgeProvider);

    // accounts が減って _selectedIndex が外を指すようになったときの保険
    if (_selectedIndex > accounts.length) {
      _selectedIndex = 0;
    }

    // 通知タブが他タブから戻ってきた瞬間、現在の個別アカウントの未読を一斉ハイライト
    ref.listen<bool>(notificationTabActiveProvider, (prev, next) {
      if (next && _selectedIndex > 0 && _selectedIndex <= accounts.length) {
        ref
            .read(notificationHighlightProvider.notifier)
            .activateForAccount(accounts[_selectedIndex - 1].id);
      }
    });

    if (accounts.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          leadingWidth: 0,
          leading: const SizedBox.shrink(),
          titleSpacing: 16,
          title: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Align(
                  alignment: const Alignment(0.03, 0.0),
                  child: Image.asset('assets/logo.png', height: 36, fit: BoxFit.contain),
                ),
              ),
              Row(
                children: [
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.settings_outlined, size: 20),
                    tooltip: '設定',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    ),
                    constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
            ],
          ),
        ),
        body: const EmptyState(
          icon: Icons.notifications_none,
          title: '通知がありません',
          subtitle: 'アカウントを追加すると通知が届きます',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leadingWidth: 0,
        leading: const SizedBox.shrink(),
        titleSpacing: 16,
        title: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Align(
                alignment: const Alignment(0.03, 0.0),
                child: Image.asset(
                  'assets/logo.png',
                  height: 36,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            Row(
              children: [
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.settings_outlined, size: 20),
                  tooltip: '設定',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  ),
                  constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(86),
          child: SizedBox(
            height: 86,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              children: [
                _AllChip(
                  selected: _selectedIndex == 0,
                  totalUnread: badge.total,
                  onTap: () => setState(() => _selectedIndex = 0),
                ),
                const SizedBox(width: 8),
                for (var i = 0; i < accounts.length; i++) ...[
                  _NotifAccountChip(
                    account: accounts[i],
                    selected: _selectedIndex == i + 1,
                    unreadCount: badge.countFor(accounts[i].id),
                    onTap: () {
                      setState(() => _selectedIndex = i + 1);
                      // 開いた瞬間にそのアカウントの未読を一斉ハイライト →
                      // 10 秒後にまとめて既読化する
                      ref
                          .read(notificationHighlightProvider.notifier)
                          .activateForAccount(accounts[i].id);
                    },
                  ),
                  if (i < accounts.length - 1) const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ),
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _UnifiedNotificationList(
            key: ValueKey(accounts.map((a) => a.id).join(',')),
            accounts: accounts,
          ),
          ...accounts.map((a) =>
              _NotificationList(key: ValueKey(a.id), account: a)),
        ],
      ),
    );
  }
}

/// 件数バッジ（999+ 対応）
class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final label = count >= 1000 ? '999+' : '$count';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.red.shade700,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.bold,
          height: 1.0,
        ),
      ),
    );
  }
}

/// 投稿画面のチップを参考にした、通知タブ用のアカウントチップ。
class _NotifAccountChip extends ConsumerWidget {
  const _NotifAccountChip({
    required this.account,
    required this.selected,
    required this.unreadCount,
    required this.onTap,
  });

  final Account account;
  final bool selected;
  final int unreadCount;
  final VoidCallback onTap;

  static Color _healthColor(AccountHealth health) {
    switch (health) {
      case AccountHealth.good:
        return Colors.green;
      case AccountHealth.warning:
        return Colors.orange;
      case AccountHealth.error:
        return Colors.red;
      case AccountHealth.unknown:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final primary = Theme.of(context).colorScheme.primary;
    final borderColor =
        selected ? primary : Theme.of(context).dividerColor;
    final fetchStatus = ref.watch(notificationFetchStatusProvider);
    final health =
        fetchStatus[account.id]?.health ?? AccountHealth.unknown;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 64,
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? primary.withValues(alpha: 0.12) : null,
          border: Border.all(
            color: borderColor,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Opacity(
              opacity: selected ? 1.0 : 0.55,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundImage: account.avatarUrl != null
                        ? NetworkImage(account.avatarUrl!)
                        : null,
                    child: account.avatarUrl == null
                        ? Text(
                            account.displayName.isNotEmpty
                                ? account.displayName[0]
                                : '?',
                            style: const TextStyle(fontSize: 12),
                          )
                        : null,
                  ),
                  Positioned(
                    right: -4,
                    bottom: -2,
                    child: SnsBadge(service: account.service, size: 7),
                  ),
                  Positioned(
                    left: -2,
                    bottom: -2,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: _healthColor(health),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                  if (unreadCount > 0)
                    Positioned(
                      left: -10,
                      top: -6,
                      child: _CountBadge(count: unreadCount),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              account.handle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight:
                    selected ? FontWeight.bold : FontWeight.normal,
                color: selected ? null : Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 「すべて」チップ。アイコン + 合計件数バッジ。
class _AllChip extends StatelessWidget {
  const _AllChip({
    required this.selected,
    required this.totalUnread,
    required this.onTap,
  });

  final bool selected;
  final int totalUnread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 64,
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? primary.withValues(alpha: 0.12) : null,
          border: Border.all(
            color: selected ? primary : Theme.of(context).dividerColor,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  Icons.all_inbox_outlined,
                  size: 30,
                  color: selected ? primary : Colors.grey[600],
                ),
                if (totalUnread > 0)
                  Positioned(
                    left: -10,
                    top: -6,
                    child: _CountBadge(count: totalUnread),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'すべて',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight:
                    selected ? FontWeight.bold : FontWeight.normal,
                color: selected ? null : Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// アカウントごとの通知リスト
class _NotificationList extends ConsumerStatefulWidget {
  const _NotificationList({super.key, required this.account});
  final Account account;

  @override
  ConsumerState<_NotificationList> createState() => _NotificationListState();
}

class _NotificationListState extends ConsumerState<_NotificationList>
    with AutomaticKeepAliveClientMixin {
  final _notifications = <NotificationItem>[];
  bool _isLoading = true;
  String? _error;
  String? _cursor;
  bool _isLoadingMore = false;
  bool _isFetching = false;
  bool _gqlFailed = false;
  DateTime? _lastFetchTime;

  /// フィルタ: 非表示にするタイプ（空 = 全表示）
  final Set<NotificationType> _hiddenTypes = {};

  List<NotificationItem> get _filteredNotifications {
    if (_hiddenTypes.isEmpty) return _notifications;
    return _notifications.where((n) => !_hiddenTypes.contains(n.type)).toList();
  }

  List<NotificationType> get _availableTypes {
    final present = _notifications.map((n) => n.type).toSet();
    return _typeOrder.where((t) => present.contains(t)).toList();
  }

  @override
  bool get wantKeepAlive => true;

  final _cacheService = NotificationCacheService.instance;

  @override
  void initState() {
    super.initState();
    // キャッシュがあれば即表示
    if (_cacheService.hasData(widget.account.id)) {
      _notifications.addAll(_cacheService.get(widget.account.id));
      _cursor = _cacheService.getCursor(widget.account.id);
      _isLoading = false;
    }
    _fetch();
  }

  Future<void> _openQueryIdWebView() async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => NotificationWebViewScreen(account: widget.account),
      ),
    );
    if (updated == true && mounted) {
      _fetch();
    }
  }

  Future<void> _fetch() async {
    if (_isFetching) return;
    _isFetching = true;
    _lastFetchTime = DateTime.now();

    final isRefresh = _notifications.isNotEmpty;
    if (!isRefresh) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final result = await fetchAccountNotifications(widget.account);
      final fetched = result.notifications;
      final newCursor = result.cursor;

      // GraphQL通知の取得結果で判定
      if (widget.account.service == SnsService.x) {
        _gqlFailed = !result.gqlOk;
      }

      if (result.updatedCreds != null) {
        await ref.read(accountProvider.notifier)
            .updateCredentials(widget.account.id, result.updatedCreds!);
      }

      if (!mounted) return;

      // キャッシュへマージ → キャッシュから最新状態を読み直す
      // merge() が同一イベント (type+targetPostId) の上書き＋再ソートを担う
      _cacheService.merge(widget.account.id, fetched, cursor: newCursor);

      setState(() {
        _notifications
          ..clear()
          ..addAll(_cacheService.get(widget.account.id));
        _cursor = _cacheService.getCursor(widget.account.id) ?? newCursor;
        _isLoading = false;
      });

      _isFetching = false;

      ref.read(activityLogProvider.notifier).logAction(
        action: ActivityAction.notificationFetch,
        platform: widget.account.service,
        accountHandle: widget.account.handle,
        accountId: widget.account.id,
        targetSummary: '${fetched.length}件取得',
        success: true,
        responseSnippet: result.responseSnippet,
      );
      ref
          .read(notificationFetchStatusProvider.notifier)
          .update(widget.account.id, true);
    } catch (e, st) {
      debugPrint('[Notifications] Error fetching for ${widget.account.handle}: $e');
      debugPrint('[Notifications] Stack: $st');

      ref.read(activityLogProvider.notifier).logAction(
        action: ActivityAction.notificationFetch,
        platform: widget.account.service,
        accountHandle: widget.account.handle,
        accountId: widget.account.id,
        success: false,
        errorMessage: '$e',
      );
      ref
          .read(notificationFetchStatusProvider.notifier)
          .update(widget.account.id, false);

      _isFetching = false;
      if (!mounted) return;

      // キャッシュデータがあればエラーを表示せず既存データを維持
      if (_notifications.isNotEmpty) {
        // 一時エラー → 無視して既存データで継続
        debugPrint('[Notifications] Transient error, keeping cached data');
        setState(() => _isLoading = false);
      } else {
        // 初回ロードで失敗 → エラー表示
        final errorStr = '$e';
        setState(() {
          _error = errorStr;
          _isLoading = false;
        });
        // 429(レート制限)以外なら自動リトライ
        if (!errorStr.contains('429')) {
          Future.delayed(const Duration(seconds: 30), () {
            if (mounted && _error != null) _fetch();
          });
        }
      }
    }
  }

  void _appendItems(List<NotificationItem> items, String? newCursor) {
    _cacheService.append(widget.account.id, items, newCursor);
    setState(() {
      _notifications
        ..clear()
        ..addAll(_cacheService.get(widget.account.id));
      _cursor = _cacheService.getCursor(widget.account.id) ?? newCursor;
      _isLoadingMore = false;
    });
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || _cursor == null) return;
    setState(() => _isLoadingMore = true);

    try {
      final result = await fetchAccountNotifications(widget.account, cursor: _cursor);
      if (result.updatedCreds != null) {
        await ref.read(accountProvider.notifier)
            .updateCredentials(widget.account.id, result.updatedCreds!);
      }
      if (!mounted) return;
      _appendItems(result.notifications, result.cursor);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // バックグラウンドフェッチで新着がある場合、自動リフェッチ（30秒クールダウン）
    final unreadAccountIds = ref.watch(notificationBadgeProvider);
    if (unreadAccountIds.contains(widget.account.id) && !_isFetching &&
        (_lastFetchTime == null || DateTime.now().difference(_lastFetchTime!) > const Duration(seconds: 30))) {
      Future.microtask(() => _fetch());
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      final friendlyError = _error!.contains('429')
          ? 'アクセスが集中しています。しばらく待ってから再読み込みしてください。'
          : _error!.contains('401') || _error!.contains('403')
              ? '認証エラーが発生しました。アカウントの再ログインが必要かもしれません。'
              : '通知の取得に失敗しました。ネットワーク接続を確認してください。';
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off, size: 48, color: Colors.grey[400]),
              const SizedBox(height: 12),
              Text(
                friendlyError,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: _fetch, child: const Text('再読み込み')),
              if (widget.account.service == SnsService.x) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _openQueryIdWebView,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('queryId 更新'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    if (_notifications.isEmpty) {
      return const EmptyState(icon: Icons.notifications_none, title: '通知はありません');
    }

    final types = _availableTypes;
    final filtered = _filteredNotifications;
    final isFiltered = _hiddenTypes.isNotEmpty;

    return Column(
      children: [
        if (_gqlFailed && widget.account.service == SnsService.x)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: Colors.orange.withAlpha(30),
            child: Row(
              children: [
                Icon(Icons.warning_amber, size: 16, color: Colors.orange[700]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'リプライ/メンション通知を取得できていません',
                    style: TextStyle(fontSize: 12, color: Colors.orange[700]),
                  ),
                ),
                TextButton(
                  onPressed: _openQueryIdWebView,
                  style: TextButton.styleFrom(
                    minimumSize: Size.zero,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('修復', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
        _NotificationTypeFilter(
          availableTypes: types,
          hiddenTypes: _hiddenTypes,
          onToggle: (type) => setState(() {
            if (_hiddenTypes.contains(type)) {
              _hiddenTypes.remove(type);
            } else {
              _hiddenTypes.add(type);
            }
          }),
          onToggleAll: (showAll) => setState(() {
            if (showAll) {
              _hiddenTypes.clear();
            } else {
              _hiddenTypes.addAll(types);
            }
          }),
        ),
        Divider(height: 1, thickness: 0.5, color: Colors.grey.withAlpha(40)),

        // 通知リスト（キャッシュ駆動で差分更新）
        Expanded(
          child: RefreshIndicator(
            onRefresh: _fetch,
            child: ListView.builder(
              itemCount:
                  filtered.length + (!isFiltered && _cursor != null ? 1 : 0),
              itemBuilder: (context, index) {
                // フィルタなし時の末尾ローディング＝loadMore トリガ
                if (!isFiltered && index == filtered.length) {
                  _loadMore();
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final n = filtered[index];
                return _NotificationTile(
                  key: ValueKey(n.id),
                  notification: n,
                  account: widget.account,
                  showSnsBadge: false,
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _NotificationTile extends ConsumerStatefulWidget {
  const _NotificationTile({
    super.key,
    required this.notification,
    required this.account,
    this.showRecipient = false,
    this.showSnsBadge = true,
    this.markSeenOnView = true,
  });
  final NotificationItem notification;
  final Account account;
  final bool showRecipient;
  final bool showSnsBadge;

  /// 「すべて」タブのように、表示しただけでは既読化したくない場合は false。
  /// 個別アカウントタブで実際にユーザーが見たときだけ既読化する。
  final bool markSeenOnView;

  @override
  ConsumerState<_NotificationTile> createState() => _NotificationTileState();
}

class _NotificationTileState extends ConsumerState<_NotificationTile> {
  NotificationItem get notification => widget.notification;
  Account get account => widget.account;
  bool get showRecipient => widget.showRecipient;

  /// システム通知かどうか（actorHandleが自分自身のアカウント）
  bool get _isSystemNotification {
    final actorHandle = notification.actorHandle.replaceFirst('@', '').toLowerCase();
    final myHandle = account.handle.replaceFirst('@', '').toLowerCase();
    return actorHandle == myHandle || actorHandle.isEmpty;
  }

  IconData get _icon => switch (notification.type) {
        NotificationType.like => Icons.favorite,
        NotificationType.repost => Icons.repeat,
        NotificationType.reply => Icons.reply,
        NotificationType.follow => Icons.person_add,
        NotificationType.mention => Icons.alternate_email,
        NotificationType.quote => Icons.format_quote,
        NotificationType.unknown => Icons.notifications,
      };

  Color get _iconColor => _typeColor(notification.type);

  List<TextSpan> _buildActorTextSpans() {
    const bold = TextStyle(fontWeight: FontWeight.bold);
    final actors = notification.additionalActors;

    if (actors.isEmpty) {
      return [
        TextSpan(text: notification.actorName, style: bold),
        TextSpan(text: ' さんが${notification.typeLabel}しました'),
      ];
    }

    final spans = <TextSpan>[
      TextSpan(text: notification.actorName, style: bold),
    ];

    if (actors.length == 1) {
      spans.add(const TextSpan(text: '、'));
      spans.add(TextSpan(text: actors[0].name, style: bold));
    } else {
      spans.add(const TextSpan(text: '、'));
      spans.add(TextSpan(text: actors[0].name, style: bold));
      spans.add(TextSpan(text: '、他${actors.length - 1}人'));
    }

    spans.add(TextSpan(text: 'が${notification.typeLabel}しました'));
    return spans;
  }

  Widget _buildAvatar(String? url, String name, {double radius = 14}) {
    return CircleAvatar(
      radius: radius,
      backgroundImage: url != null ? NetworkImage(url) : null,
      child: url == null
          ? Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: TextStyle(fontSize: radius * 0.7),
            )
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    // ハイライト判定はグローバル provider に集約。
    // 「すべて」タブ（markSeenOnView=false）ではハイライトもしない。
    final highlighted = widget.markSeenOnView &&
        ref
            .watch(notificationHighlightProvider)
            .contains(notification.id);

    final timeAgo = _formatTimeAgo(notification.timestamp);
    final actors = notification.additionalActors;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeOut,
      color: highlighted
          ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.15)
          : null,
      child: InkWell(
        onTap: () {
          if (_isSystemNotification) {
            final fullText = '${notification.actorName} ${notification.targetPostBody ?? ''}';
            showAppSnackBar(context, fullText, duration: const Duration(seconds: 5));
            return;
          }
          if (notification.type == NotificationType.follow ||
              notification.targetPostId == null) {
            _navigateToActorProfile(context);
          } else {
            _navigateToTargetPost(context);
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 通知種類アイコン（大きめ）
              SizedBox(
                width: 36,
                child: Column(
                  children: [
                    Icon(_icon, size: 24, color: _iconColor),
                    if (widget.showSnsBadge) ...[
                      const SizedBox(height: 4),
                      SnsBadge(service: notification.source, size: 10),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // メインコンテンツ
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // アクターアバター横並び + 時間
                    Row(
                      children: [
                        GestureDetector(
                          onTap: _isSystemNotification ? null : () => _navigateToActorProfile(context),
                          child: _buildAvatar(notification.actorAvatarUrl, notification.actorName),
                        ),
                        for (var i = 0; i < actors.length && i < 4; i++) ...[
                          const SizedBox(width: 4),
                          _buildAvatar(actors[i].avatarUrl, actors[i].name, radius: 12),
                        ],
                        if (actors.length > 4) ...[
                          const SizedBox(width: 4),
                          Text('+${actors.length - 4}', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                        ],
                        const Spacer(),
                        Text(timeAgo, style: TextStyle(color: Colors.grey[500], fontSize: 11)),
                        if (showRecipient) ...[
                          const SizedBox(width: 6),
                          Opacity(
                            opacity: 0.5,
                            child: _buildAvatar(account.avatarUrl, account.displayName, radius: 8),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    // 「誰が何をした」
                    Text.rich(
                      TextSpan(children: _buildActorTextSpans()),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                    // 対象投稿本文
                    if (notification.targetPostBody != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        notification.targetPostBody!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      ),
        Divider(height: 1, thickness: 0.5, color: Colors.grey.withAlpha(40)),
      ],
    );
  }

  void _navigateToActorProfile(BuildContext context) {
    // actorHandle has '@' prefix — strip it for UserProfileScreen
    final handle = notification.actorHandle.startsWith('@')
        ? notification.actorHandle.substring(1)
        : notification.actorHandle;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UserProfileScreen(
          username: notification.actorName,
          handle: handle,
          service: notification.source,
          avatarUrl: notification.actorAvatarUrl,
          accountId: account.id,
        ),
      ),
    );
  }

  /// 通知の対象投稿を取得して PostDetailScreen へ遷移
  Future<void> _navigateToTargetPost(BuildContext context) async {
    final postId = notification.targetPostId;
    if (postId == null) {
      _navigateToActorProfile(context);
      return;
    }

    // ローディング表示（ルートNavigatorで表示）
    showDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      List<Post> posts;
      if (notification.source == SnsService.x) {
        posts = await XApiService.instance.getTweetDetail(
          account.xCredentials,
          postId,
          accountId: account.id,
        );
      } else {
        posts = await BlueskyApiService.instance.getPostThread(
          account.blueskyCredentials,
          postId,
          accountId: account.id,
        );
      }

      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // ローディングを閉じる

      if (posts.isNotEmpty) {
        // 通知対象の投稿をスレッド内から探す（リプライ通知ならリプライ自体）
        final targetId = notification.source == SnsService.x ? 'x_$postId' : 'bsky_$postId';
        final target = posts.firstWhere(
          (p) => p.id == targetId,
          orElse: () => posts.first,
        );
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PostDetailScreen(post: target),
          ),
        );
      } else {
        showAppSnackBar(context, '投稿が見つかりませんでした', type: SnackType.error);
      }
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // ローディングを閉じる
      showAppSnackBar(context, '投稿の読み込みに失敗しました: $e', type: SnackType.error);
    }
  }

  String _formatTimeAgo(DateTime ts) {
    final diff = DateTime.now().difference(ts);
    if (diff.inMinutes < 1) return '今';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分';
    if (diff.inHours < 24) return '${diff.inHours}時間';
    if (diff.inDays < 7) return '${diff.inDays}日';
    return '${ts.month}/${ts.day}';
  }
}

// ─── 統合通知リスト（「すべて」タブ） ───

class _UnifiedNotificationList extends ConsumerStatefulWidget {
  const _UnifiedNotificationList({super.key, required this.accounts});
  final List<Account> accounts;

  @override
  ConsumerState<_UnifiedNotificationList> createState() =>
      _UnifiedNotificationListState();
}

class _UnifiedNotificationListState
    extends ConsumerState<_UnifiedNotificationList>
    with AutomaticKeepAliveClientMixin {
  bool _isLoading = true;
  bool _isFetching = false;
  DateTime? _lastFetchTime;
  List<NotificationItem> _allNotifications = [];

  final Set<NotificationType> _hiddenTypes = {};

  final _cacheService = NotificationCacheService.instance;

  @override
  bool get wantKeepAlive => true;

  List<NotificationItem> get _filteredNotifications {
    if (_hiddenTypes.isEmpty) return _allNotifications;
    return _allNotifications.where((n) => !_hiddenTypes.contains(n.type)).toList();
  }

  List<NotificationType> get _availableTypes {
    final present = _allNotifications.map((n) => n.type).toSet();
    return _typeOrder.where((t) => present.contains(t)).toList();
  }

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didUpdateWidget(covariant _UnifiedNotificationList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldIds = oldWidget.accounts.map((a) => a.id).toSet();
    final newIds = widget.accounts.map((a) => a.id).toSet();
    if (!oldIds.containsAll(newIds) || !newIds.containsAll(oldIds)) {
      _init();
    }
  }

  void _init() {
    _loadFromCache();
    _fetchAll();
  }

  void _loadFromCache() {
    final accountIds = widget.accounts.map((a) => a.id).toList();
    _allNotifications = _cacheService.getAllMerged(accountIds);
    if (_allNotifications.isNotEmpty) {
      _isLoading = false;
    }
  }

  Future<void> _fetchAll() async {
    if (_isFetching) return;
    _isFetching = true;
    _lastFetchTime = DateTime.now();

    try {
      final futures = widget.accounts.map((account) async {
        try {
          final result = await fetchAccountNotifications(account);
          _cacheService.merge(account.id, result.notifications, cursor: result.cursor);
          if (result.updatedCreds != null) {
            ref.read(accountProvider.notifier)
                .updateCredentials(account.id, result.updatedCreds!);
          }
          ref
              .read(notificationFetchStatusProvider.notifier)
              .update(account.id, true);
        } catch (e) {
          debugPrint('[UnifiedNotif] Error fetching ${account.handle}: $e');
          ref
              .read(notificationFetchStatusProvider.notifier)
              .update(account.id, false);
        }
      });

      await Future.wait(futures);

      if (!mounted) return;
      _loadFromCache();
      setState(() {
        _isLoading = false;
      });
    } finally {
      _isFetching = false;
    }
  }

  Account? _accountForNotification(NotificationItem n) {
    if (n.accountId == null) return null;
    return widget.accounts.where((a) => a.id == n.accountId).firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // バックグラウンドフェッチで新着がある場合、自動リフェッチ（30秒クールダウン）
    final unreadAccountIds = ref.watch(notificationBadgeProvider);
    if (unreadAccountIds.isNotEmpty && !_isFetching &&
        (_lastFetchTime == null || DateTime.now().difference(_lastFetchTime!) > const Duration(seconds: 30))) {
      Future.microtask(() => _fetchAll());
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_allNotifications.isEmpty) {
      return const EmptyState(icon: Icons.notifications_none, title: '通知はありません');
    }

    final types = _availableTypes;
    final filtered = _filteredNotifications;

    return Column(
      children: [
        _NotificationTypeFilter(
          availableTypes: types,
          hiddenTypes: _hiddenTypes,
          onToggle: (type) => setState(() {
            if (_hiddenTypes.contains(type)) {
              _hiddenTypes.remove(type);
            } else {
              _hiddenTypes.add(type);
            }
          }),
          onToggleAll: (showAll) => setState(() {
            if (showAll) {
              _hiddenTypes.clear();
            } else {
              _hiddenTypes.addAll(types);
            }
          }),
        ),
        Divider(height: 1, thickness: 0.5, color: Colors.grey.withAlpha(40)),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _fetchAll,
            child: ListView.builder(
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final n = filtered[index];
                final account = _accountForNotification(n);
                if (account == null) return const SizedBox.shrink();
                return _NotificationTile(
                  key: ValueKey(n.id),
                  notification: n,
                  account: account,
                  showRecipient: true,
                  markSeenOnView: false, // 「すべて」タブは未読のまま保持
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

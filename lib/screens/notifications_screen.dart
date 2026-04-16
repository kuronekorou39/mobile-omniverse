import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/account.dart';
import '../models/activity_log.dart';
import '../models/notification_item.dart';
import '../models/post.dart';
import '../models/sns_service.dart';
import '../providers/account_provider.dart';
import '../providers/activity_log_provider.dart';
import '../providers/notification_badge_provider.dart';
import '../services/account_storage_service.dart';
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

    final merged = [...notifResult.notifications, ...gqlResult.notifications];
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

class _NotificationsScreenState extends ConsumerState<NotificationsScreen>
    with TickerProviderStateMixin {
  TabController? _tabController;

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountProvider).where((a) => a.isEnabled).toList();

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

    // タブ数: 「すべて」+ 各アカウント
    final tabCount = accounts.length + 1;
    if (_tabController == null || _tabController!.length != tabCount) {
      _tabController?.dispose();
      _tabController = TabController(length: tabCount, vsync: this);
    }

    final unreadAccountIds = ref.watch(notificationBadgeProvider);
    final hasAnyUnread = unreadAccountIds.isNotEmpty;

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
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: [
            // 「すべて」タブ
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('すべて'),
                  if (hasAnyUnread) ...[
                    const SizedBox(width: 6),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // 各アカウントタブ
            ...accounts.map((a) {
              final hasNew = unreadAccountIds.contains(a.id);
              return Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SnsBadge(service: a.service, size: 12),
                    const SizedBox(width: 4),
                    CircleAvatar(
                      radius: 10,
                      backgroundImage: a.avatarUrl != null
                          ? NetworkImage(a.avatarUrl!)
                          : null,
                      child: a.avatarUrl == null
                          ? Text(
                              a.displayName.isNotEmpty
                                  ? a.displayName[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(fontSize: 9),
                            )
                          : null,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        a.displayName,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (hasNew) ...[
                      const SizedBox(width: 6),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _UnifiedNotificationList(accounts: accounts),
          ...accounts.map((a) => _NotificationList(account: a)),
        ],
      ),
    );
  }
}

/// アカウントごとの通知リスト
class _NotificationList extends ConsumerStatefulWidget {
  const _NotificationList({required this.account});
  final Account account;

  @override
  ConsumerState<_NotificationList> createState() => _NotificationListState();
}

class _NotificationListState extends ConsumerState<_NotificationList>
    with AutomaticKeepAliveClientMixin {
  final _notifications = <NotificationItem>[];
  final _listKey = GlobalKey<AnimatedListState>();
  bool _isLoading = true;
  String? _error;
  String? _cursor;
  bool _isLoadingMore = false;
  bool _isFetching = false;
  bool _gqlFailed = false;
  late DateTime _readLine;

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
    _readLine = _cacheService.openTab(widget.account.id);
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

      if (isRefresh) {
        // 既存 + 新規をマージして時系列ソート
        final existingIds = _notifications.map((n) => n.id).toSet();
        final newItems = fetched.where((n) => !existingIds.contains(n.id)).toList();
        if (newItems.isNotEmpty) {
          _notifications.addAll(newItems);
          _notifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));
          // AnimatedList を全件リビルド
          for (var i = 0; i < newItems.length; i++) {
            final idx = _notifications.indexOf(newItems[i]);
            _listKey.currentState?.insertItem(idx,
                duration: const Duration(milliseconds: 300));
          }
        }
        setState(() => _cursor = newCursor);
      } else {
        // 初回ロード: 全件セット（fetchedはソート済み）
        _notifications.addAll(fetched);
        setState(() {
          _cursor = newCursor;
          _isLoading = false;
        });
      }

      // キャッシュに同期
      _cacheService.merge(widget.account.id, fetched, cursor: newCursor);

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

      _isFetching = false;
      if (!mounted) return;

      // キャッシュデータがあればエラーを表示せず既存データを維持
      if (_notifications.isNotEmpty) {
        // 一時エラー → 無視して既存データで継続
        debugPrint('[Notifications] Transient error, keeping cached data');
        setState(() => _isLoading = false);
      } else {
        // 初回ロードで失敗 → エラー表示 + 自動リトライ
        setState(() {
          _error = '$e';
          _isLoading = false;
        });
        Future.delayed(const Duration(seconds: 10), () {
          if (mounted && _error != null) _fetch();
        });
      }
    }
  }

  void _appendItems(List<NotificationItem> items, String? newCursor) {
    final startIndex = _notifications.length;
    _notifications.addAll(items);
    for (var i = 0; i < items.length; i++) {
      _listKey.currentState?.insertItem(startIndex + i,
          duration: const Duration(milliseconds: 200));
    }
    setState(() {
      _cursor = newCursor;
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

    // バックグラウンドフェッチで新着がある場合、自動リフェッチ
    final unreadAccountIds = ref.watch(notificationBadgeProvider);
    if (unreadAccountIds.contains(widget.account.id) && !_isFetching) {
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

        // 通知リスト
        Expanded(
          child: RefreshIndicator(
            onRefresh: _fetch,
            child: isFiltered
                // フィルタ中は通常ListView（AnimatedListはフィルタと相性が悪い）
                ? ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final n = filtered[index];
                      return _NotificationTile(
                        notification: n,
                        account: widget.account,
                        isNew: n.timestamp.isAfter(_readLine),
                        showSnsBadge: false,
                      );
                    },
                  )
                // フィルタなしはAnimatedList（新着アニメーション対応）
                : AnimatedList(
                    key: _listKey,
                    initialItemCount: _notifications.length + (_cursor != null ? 1 : 0),
                    itemBuilder: (context, index, animation) {
                      if (index == _notifications.length) {
                        _loadMore();
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      final n = _notifications[index];
                      return SizeTransition(
                        sizeFactor: animation,
                        child: _NotificationTile(
                          notification: n,
                          account: widget.account,
                          isNew: n.timestamp.isAfter(_readLine),
                          showSnsBadge: false,
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

class _NotificationTile extends StatefulWidget {
  const _NotificationTile({
    required this.notification,
    required this.account,
    this.isNew = false,
    this.showRecipient = false,
    this.showSnsBadge = true,
  });
  final NotificationItem notification;
  final Account account;
  final bool isNew;
  final bool showRecipient;
  final bool showSnsBadge;

  @override
  State<_NotificationTile> createState() => _NotificationTileState();
}

class _NotificationTileState extends State<_NotificationTile> {
  double _highlightOpacity = 0.0;

  NotificationItem get notification => widget.notification;
  Account get account => widget.account;
  bool get showRecipient => widget.showRecipient;

  @override
  void initState() {
    super.initState();
    _activateHighlight();
  }

  @override
  void didUpdateWidget(covariant _NotificationTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isNew && !oldWidget.isNew) {
      _activateHighlight();
    }
  }

  void _activateHighlight() {
    if (!widget.isNew) return;
    setState(() => _highlightOpacity = 1.0);
    Future.delayed(const Duration(seconds: 10), () {
      if (mounted) setState(() => _highlightOpacity = 0.0);
    });
  }

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
    final timeAgo = _formatTimeAgo(notification.timestamp);
    final actors = notification.additionalActors;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
      duration: const Duration(seconds: 3),
      curve: Curves.easeOut,
      color: _highlightOpacity > 0
          ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.15 * _highlightOpacity)
          : null,
      child: InkWell(
        onTap: () {
          if (_isSystemNotification) {
            final fullText = '${notification.actorName} ${notification.targetPostBody ?? ''}';
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(fullText), duration: const Duration(seconds: 5)),
            );
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('投稿が見つかりませんでした')),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // ローディングを閉じる
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('投稿の読み込みに失敗しました: $e')),
      );
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
  const _UnifiedNotificationList({required this.accounts});
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
  List<NotificationItem> _allNotifications = [];
  late DateTime _readLine;

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
    final accountIds = widget.accounts.map((a) => a.id).toList();
    _readLine = _cacheService.openAllTab(accountIds);
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

    try {
      final futures = widget.accounts.map((account) async {
        try {
          final result = await fetchAccountNotifications(account);
          _cacheService.merge(account.id, result.notifications, cursor: result.cursor);
          if (result.updatedCreds != null) {
            ref.read(accountProvider.notifier)
                .updateCredentials(account.id, result.updatedCreds!);
          }
        } catch (e) {
          debugPrint('[UnifiedNotif] Error fetching ${account.handle}: $e');
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

    // バックグラウンドフェッチで新着がある場合、自動リフェッチ
    final unreadAccountIds = ref.watch(notificationBadgeProvider);
    if (unreadAccountIds.isNotEmpty && !_isFetching) {
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
                  notification: n,
                  account: account,
                  isNew: n.timestamp.isAfter(_readLine),
                  showRecipient: true,
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

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
import '../widgets/sns_badge.dart';
import 'post_detail_screen.dart';
import 'user_profile_screen.dart';

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
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🔔', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 12),
              Text(
                'シーン...',
                style: TextStyle(fontSize: 16, color: Colors.grey[500]),
              ),
              const SizedBox(height: 4),
              Text(
                'アカウントを追加すると通知が届きます',
                style: TextStyle(fontSize: 13, color: Colors.grey[400]),
              ),
            ],
          ),
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
        toolbarHeight: 8,
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
      late final int count;
      String? responseSnippet;
      late final List<NotificationItem> fetched;
      late final String? newCursor;

      if (widget.account.service == SnsService.x) {
        // 通知 + メンション（リプライ）を並列取得
        final results = await Future.wait([
          XApiService.instance.getNotifications(widget.account.xCredentials),
          XApiService.instance.getMentionNotifications(widget.account.xCredentials),
        ]);
        final notifResult = results[0] as ({List<NotificationItem> notifications, String? cursor, String? responseSnippet});
        final mentions = results[1] as List<NotificationItem>;

        // 統合してタイムスタンプ順にソート
        final merged = [...notifResult.notifications, ...mentions];
        // 重複排除（同じIDがある場合）
        final seen = <String>{};
        merged.retainWhere((n) => seen.add(n.id));
        merged.sort((a, b) => b.timestamp.compareTo(a.timestamp));

        count = merged.length;
        responseSnippet = notifResult.responseSnippet;
        fetched = merged;
        newCursor = notifResult.cursor;
      } else {
        final result = await BlueskyApiService.instance
            .getNotificationsWithRefresh(widget.account.blueskyCredentials);
        count = result.notifications.length;
        fetched = result.notifications;
        newCursor = result.cursor;
        if (result.updatedCreds != null) {
          await ref.read(accountProvider.notifier)
              .updateCredentials(widget.account.id, result.updatedCreds!);
        }
      }

      if (!mounted) return;

      if (isRefresh) {
        // 既存のIDセットと比較して新しい通知だけを挿入
        final existingIds = _notifications.map((n) => n.id).toSet();
        final newItems = fetched.where((n) => !existingIds.contains(n.id)).toList();
        if (newItems.isNotEmpty) {
          for (var i = 0; i < newItems.length; i++) {
            _notifications.insert(i, newItems[i]);
            _listKey.currentState?.insertItem(i,
                duration: const Duration(milliseconds: 300));
          }
        }
        setState(() => _cursor = newCursor);
      } else {
        // 初回ロード: 全件セット
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
        targetSummary: '$count件取得',
        success: true,
        responseSnippet: responseSnippet,
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
      if (widget.account.service == SnsService.x) {
        final result = await XApiService.instance
            .getNotifications(widget.account.xCredentials, cursor: _cursor);
        if (!mounted) return;
        _appendItems(result.notifications, result.cursor);
      } else {
        final result = await BlueskyApiService.instance
            .getNotificationsWithRefresh(
                widget.account.blueskyCredentials,
                cursor: _cursor);
        if (result.updatedCreds != null) {
          await ref.read(accountProvider.notifier)
              .updateCredentials(widget.account.id, result.updatedCreds!);
        }
        if (!mounted) return;
        _appendItems(result.notifications, result.cursor);
      }
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
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            FilledButton(onPressed: _fetch, child: const Text('再読み込み')),
          ],
        ),
      );
    }

    if (_notifications.isEmpty) {
      return const Center(child: Text('通知はありません'));
    }

    final types = _availableTypes;
    final filtered = _filteredNotifications;
    final isFiltered = _hiddenTypes.isNotEmpty;

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
                        isNew: _cacheService.isNew(widget.account.id, n.id),
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
                          isNew: _cacheService.isNew(widget.account.id, n.id),
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
  });
  final NotificationItem notification;
  final Account account;
  final bool isNew;
  final bool showRecipient;

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
    if (widget.isNew) {
      _highlightOpacity = 1.0;
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) setState(() => _highlightOpacity = 0.0);
      });
    }
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

  @override
  Widget build(BuildContext context) {
    final timeAgo = _formatTimeAgo(notification.timestamp);

    return AnimatedContainer(
      duration: const Duration(seconds: 3),
      curve: Curves.easeOut,
      color: _highlightOpacity > 0
          ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.2 * _highlightOpacity)
          : null,
      child: ListTile(
      leading: GestureDetector(
        onTap: _isSystemNotification ? null : () => _navigateToActorProfile(context),
        child: SizedBox(
          width: notification.additionalActors.isNotEmpty ? 56 : 44,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 追加アクターのアバター（2人目以降、右下にずらして重ねる）
              for (var i = (notification.additionalActors.length > 2 ? 1 : notification.additionalActors.length - 1); i >= 0; i--)
                Positioned(
                  left: 16 + (i * 4).toDouble(),
                  top: 10 + (i * 4).toDouble(),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        width: 1.5,
                      ),
                    ),
                    child: CircleAvatar(
                      radius: 14,
                      backgroundImage: notification.additionalActors[i].avatarUrl != null
                          ? NetworkImage(notification.additionalActors[i].avatarUrl!)
                          : null,
                      child: notification.additionalActors[i].avatarUrl == null
                          ? Text(
                              notification.additionalActors[i].name.isNotEmpty
                                  ? notification.additionalActors[i].name[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(fontSize: 10),
                            )
                          : null,
                    ),
                  ),
                ),
              // メインアクターのアバター（最前面）
              CircleAvatar(
                radius: 20,
                backgroundImage: notification.actorAvatarUrl != null
                    ? NetworkImage(notification.actorAvatarUrl!)
                    : null,
                child: notification.actorAvatarUrl == null
                    ? Text(
                        notification.actorName.isNotEmpty
                            ? notification.actorName[0].toUpperCase()
                            : '?',
                      )
                    : null,
              ),
              Positioned(
                bottom: 0,
                right: notification.additionalActors.isNotEmpty ? 12 : 0,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(_icon, size: 14, color: _iconColor),
                ),
              ),
              Positioned(
                top: -4,
                left: -6,
                child: SnsBadge(service: notification.source, size: 10),
              ),
            ],
          ),
        ),
      ),
      title: Text.rich(
        TextSpan(children: _buildActorTextSpans()),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: notification.targetPostBody != null
          ? Text(
              notification.targetPostBody!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            )
          : null,
      trailing: SizedBox(
        width: 48,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              timeAgo,
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
          if (showRecipient) ...[
            const SizedBox(height: 4),
            CircleAvatar(
              radius: 10,
              backgroundImage: account.avatarUrl != null
                  ? NetworkImage(account.avatarUrl!)
                  : null,
              child: account.avatarUrl == null
                  ? Text(
                      account.displayName.isNotEmpty
                          ? account.displayName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(fontSize: 9),
                    )
                  : null,
            ),
          ],
        ],
        ),
      ),
      contentPadding: const EdgeInsets.only(left: 16, right: 8, top: 4, bottom: 4),
      onTap: () {
        if (_isSystemNotification) {
          // システム通知 → 全文をスナックバーで表示
          final fullText = '${notification.actorName} ${notification.targetPostBody ?? ''}';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(fullText),
              duration: const Duration(seconds: 5),
            ),
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
      ),
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
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PostDetailScreen(post: posts.first),
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
          if (account.service == SnsService.x) {
            final results = await Future.wait([
              XApiService.instance.getNotifications(account.xCredentials),
              XApiService.instance.getMentionNotifications(account.xCredentials),
            ]);
            final notifResult = results[0] as ({List<NotificationItem> notifications, String? cursor, String? responseSnippet});
            final mentions = results[1] as List<NotificationItem>;
            final merged = [...notifResult.notifications, ...mentions];
            final seen = <String>{};
            merged.retainWhere((n) => seen.add(n.id));
            merged.sort((a, b) => b.timestamp.compareTo(a.timestamp));
            _cacheService.merge(account.id, merged, cursor: notifResult.cursor);
          } else {
            final result = await BlueskyApiService.instance
                .getNotificationsWithRefresh(account.blueskyCredentials);
            _cacheService.merge(account.id, result.notifications, cursor: result.cursor);
            if (result.updatedCreds != null) {
              ref.read(accountProvider.notifier)
                  .updateCredentials(account.id, result.updatedCreds!);
            }
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
      return const Center(child: Text('通知はありません'));
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
                  isNew: _cacheService.isNew(account.id, n.id),
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

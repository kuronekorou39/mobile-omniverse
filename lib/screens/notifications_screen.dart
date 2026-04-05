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
        appBar: AppBar(title: const Text('通知')),
        body: const Center(child: Text('有効なアカウントがありません')),
      );
    }

    // タブ数が変わったらコントローラを再作成
    if (_tabController == null || _tabController!.length != accounts.length) {
      _tabController?.dispose();
      _tabController = TabController(length: accounts.length, vsync: this);
    }

    final unreadAccountIds = ref.watch(notificationBadgeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('通知'),
        bottom: accounts.length > 1
            ? TabBar(
                controller: _tabController,
                isScrollable: accounts.length > 3,
                tabs: accounts.map((a) {
                  final hasNew = unreadAccountIds.contains(a.id);
                  return Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SnsBadge(service: a.service),
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
                }).toList(),
              )
            : null,
      ),
      body: accounts.length == 1
          ? _NotificationList(account: accounts.first)
          : TabBarView(
              controller: _tabController,
              children: accounts
                  .map((a) => _NotificationList(account: a))
                  .toList(),
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

  /// フィルタ: 表示するタイプ（空 = 全表示）
  final Set<NotificationType> _activeFilters = {};

  List<NotificationItem> get _filteredNotifications {
    if (_activeFilters.isEmpty) return _notifications;
    return _notifications.where((n) => _activeFilters.contains(n.type)).toList();
  }

  /// 通知リストに含まれるタイプ一覧（表示順固定）
  List<NotificationType> get _availableTypes {
    const order = [
      NotificationType.like,
      NotificationType.repost,
      NotificationType.reply,
      NotificationType.mention,
      NotificationType.quote,
      NotificationType.follow,
      NotificationType.unknown,
    ];
    final present = _notifications.map((n) => n.type).toSet();
    return order.where((t) => present.contains(t)).toList();
  }

  String _typeLabel(NotificationType type) => switch (type) {
        NotificationType.like => 'いいね',
        NotificationType.repost => 'リポスト',
        NotificationType.reply => 'リプライ',
        NotificationType.mention => 'メンション',
        NotificationType.quote => '引用',
        NotificationType.follow => 'フォロー',
        NotificationType.unknown => 'その他',
      };

  IconData _typeIcon(NotificationType type) => switch (type) {
        NotificationType.like => Icons.favorite,
        NotificationType.repost => Icons.repeat,
        NotificationType.reply => Icons.reply,
        NotificationType.mention => Icons.alternate_email,
        NotificationType.quote => Icons.format_quote,
        NotificationType.follow => Icons.person_add,
        NotificationType.unknown => Icons.notifications,
      };

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

      if (!mounted) return;
      setState(() {
        _error = '$e';
        _isLoading = false;
      });
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
    final isFiltered = _activeFilters.isNotEmpty;

    return Column(
      children: [
        // フィルタチップ
        if (types.length > 1)
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              children: types.map((type) {
                final isActive = _activeFilters.contains(type);
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Icon(_typeIcon(type), size: 16),
                    selected: isActive,
                    onSelected: (_) {
                      setState(() {
                        if (isActive) {
                          _activeFilters.remove(type);
                        } else {
                          _activeFilters.add(type);
                        }
                      });
                    },
                    tooltip: _typeLabel(type),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    labelPadding: EdgeInsets.zero,
                  ),
                );
              }).toList(),
            ),
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

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.notification,
    required this.account,
    this.isNew = false,
  });
  final NotificationItem notification;
  final Account account;
  final bool isNew;

  IconData get _icon => switch (notification.type) {
        NotificationType.like => Icons.favorite,
        NotificationType.repost => Icons.repeat,
        NotificationType.reply => Icons.reply,
        NotificationType.follow => Icons.person_add,
        NotificationType.mention => Icons.alternate_email,
        NotificationType.quote => Icons.format_quote,
        NotificationType.unknown => Icons.notifications,
      };

  Color get _iconColor => switch (notification.type) {
        NotificationType.like => Colors.pink,
        NotificationType.repost => Colors.green,
        NotificationType.reply => Colors.blue,
        NotificationType.follow => Colors.purple,
        NotificationType.mention => Colors.orange,
        NotificationType.quote => Colors.teal,
        NotificationType.unknown => Colors.grey,
      };

  @override
  Widget build(BuildContext context) {
    final timeAgo = _formatTimeAgo(notification.timestamp);

    return ListTile(
      tileColor: isNew
          ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.15)
          : null,
      leading: GestureDetector(
        onTap: () => _navigateToActorProfile(context),
        child: SizedBox(
          width: 44,
          child: Stack(
            children: [
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
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(_icon, size: 14, color: _iconColor),
                ),
              ),
            ],
          ),
        ),
      ),
      title: RichText(
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        text: TextSpan(
          style: DefaultTextStyle.of(context).style,
          children: [
            TextSpan(
              text: notification.actorName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            TextSpan(text: ' さんが${notification.typeLabel}しました'),
          ],
        ),
      ),
      subtitle: notification.targetPostBody != null
          ? Text(
              notification.targetPostBody!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            )
          : null,
      trailing: Text(
        timeAgo,
        style: TextStyle(color: Colors.grey[500], fontSize: 12),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      onTap: () {
        if (notification.type == NotificationType.follow ||
            notification.targetPostId == null) {
          _navigateToActorProfile(context);
        } else {
          _navigateToTargetPost(context);
        }
      },
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

    // ローディング表示
    showDialog(
      context: context,
      barrierDismissible: false,
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
      Navigator.of(context).pop(); // ローディングを閉じる

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
      Navigator.of(context).pop(); // ローディングを閉じる
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

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
import '../services/bluesky_api_service.dart';
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('通知'),
        bottom: accounts.length > 1
            ? TabBar(
                controller: _tabController,
                isScrollable: accounts.length > 3,
                tabs: accounts.map((a) {
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
  bool _isLoading = true;
  String? _error;
  String? _cursor;
  bool _isLoadingMore = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      late final int count;
      String? responseSnippet;

      if (widget.account.service == SnsService.x) {
        final result = await XApiService.instance
            .getNotifications(widget.account.xCredentials);
        count = result.notifications.length;
        responseSnippet = result.responseSnippet;
        if (!mounted) return;
        setState(() {
          _notifications
            ..clear()
            ..addAll(result.notifications);
          _cursor = result.cursor;
          _isLoading = false;
        });
      } else {
        final result = await BlueskyApiService.instance
            .getNotifications(widget.account.blueskyCredentials);
        count = result.notifications.length;
        if (!mounted) return;
        setState(() {
          _notifications
            ..clear()
            ..addAll(result.notifications);
          _cursor = result.cursor;
          _isLoading = false;
        });
      }

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

  Future<void> _loadMore() async {
    if (_isLoadingMore || _cursor == null) return;
    setState(() => _isLoadingMore = true);

    try {
      if (widget.account.service == SnsService.x) {
        final result = await XApiService.instance
            .getNotifications(widget.account.xCredentials, cursor: _cursor);
        if (!mounted) return;
        setState(() {
          _notifications.addAll(result.notifications);
          _cursor = result.cursor;
          _isLoadingMore = false;
        });
      } else {
        final result = await BlueskyApiService.instance.getNotifications(
            widget.account.blueskyCredentials,
            cursor: _cursor);
        if (!mounted) return;
        setState(() {
          _notifications.addAll(result.notifications);
          _cursor = result.cursor;
          _isLoadingMore = false;
        });
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

    return RefreshIndicator(
      onRefresh: _fetch,
      child: ListView.builder(
        itemCount: _notifications.length + (_cursor != null ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _notifications.length) {
            // ページネーションローダー
            _loadMore();
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return _NotificationTile(
            notification: _notifications[index],
            account: widget.account,
          );
        },
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.notification,
    required this.account,
  });
  final NotificationItem notification;
  final Account account;

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

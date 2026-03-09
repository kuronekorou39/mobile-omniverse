import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/account.dart';
import '../models/notification_item.dart';
import '../models/sns_service.dart';
import '../providers/account_provider.dart';
import '../services/bluesky_api_service.dart';
import '../services/x_api_service.dart';
import '../widgets/sns_badge.dart';

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
class _NotificationList extends StatefulWidget {
  const _NotificationList({required this.account});
  final Account account;

  @override
  State<_NotificationList> createState() => _NotificationListState();
}

class _NotificationListState extends State<_NotificationList>
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
      if (widget.account.service == SnsService.x) {
        final result = await XApiService.instance
            .getNotifications(widget.account.xCredentials);
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
        if (!mounted) return;
        setState(() {
          _notifications
            ..clear()
            ..addAll(result.notifications);
          _cursor = result.cursor;
          _isLoading = false;
        });
      }
    } catch (e) {
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
          return _NotificationTile(notification: _notifications[index]);
        },
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification});
  final NotificationItem notification;

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
      leading: SizedBox(
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
    );
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

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/account_storage_service.dart';
import '../services/notification_cache_service.dart';
import 'notification_badge_provider.dart';

/// アカウントの通知リストを見た瞬間に、そのアカウントの未読をまとめて既読にし、
/// どれが新しかったかを少しのあいだハイライトで示す。state はハイライト中の
/// 通知 id。
///
/// 既読化とバッジの数字はすぐ反映する。数字まで [_holdDuration] 待たせると
/// 「見たのに消えない」になる。待つのはハイライトを消すほうだけ。
///
/// ハイライトする対象は見た時点の未読を一斉に取る。行が画面に入るたびに
/// 光らせると、上が消えたあとスクロールした先でまた光ることになる。
class NotificationHighlightNotifier extends StateNotifier<Set<String>> {
  NotificationHighlightNotifier(this._ref) : super(const {});

  final Ref _ref;
  static const _holdDuration = Duration(seconds: 5);

  /// アカウント単位の、ハイライトを消すタイマー
  final Map<String, Timer> _timers = {};

  /// アカウント単位の、いまハイライトしている通知
  final Map<String, Set<String>> _highlightedByAccount = {};

  /// 指定アカウントの未読を既読にして、ハイライトに登録する。
  /// ハイライト中にもう一度呼ばれたら、新しいぶんを足して消すまでの時間を
  /// 取り直す。
  /// システム通知（鈴マーク）はバッジ件数だけでなくハイライトからも除外する。
  void activateForAccount(String accountId) {
    final cache = NotificationCacheService.instance;
    final account = AccountStorageService.instance.accounts
        .where((a) => a.id == accountId)
        .firstOrNull;
    if (account == null) return;
    final unread =
        cache.unseenItemsExcludingSystem(accountId, account.handle);
    if (unread.isEmpty) return;

    for (final n in unread) {
      cache.markSeen(n);
    }
    final ids = unread.map((n) => n.id).toSet();
    (_highlightedByAccount[accountId] ??= {}).addAll(ids);
    state = {...state, ...ids};
    _ref.read(notificationBadgeProvider.notifier).refreshBadge();

    _timers[accountId]?.cancel();
    _timers[accountId] = Timer(_holdDuration, () => _fade(accountId));
  }

  void _fade(String accountId) {
    _timers.remove(accountId);
    final ids = _highlightedByAccount.remove(accountId);
    if (ids == null || ids.isEmpty) return;
    state = state.difference(ids);
  }

  bool isHighlighted(String notificationId) =>
      state.contains(notificationId);

  @override
  void dispose() {
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    _highlightedByAccount.clear();
    super.dispose();
  }
}

final notificationHighlightProvider =
    StateNotifierProvider<NotificationHighlightNotifier, Set<String>>(
  (ref) {
    final notifier = NotificationHighlightNotifier(ref);
    if (kDebugMode) {
      ref.onDispose(() => debugPrint('[NotifHighlight] disposed'));
    }
    return notifier;
  },
);

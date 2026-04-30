import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/account_storage_service.dart';
import '../services/notification_cache_service.dart';
import 'notification_badge_provider.dart';

/// アカウントタブを開いた瞬間に、そのアカウントの未読通知 id を一斉にスナップ
/// ショットして state に積む。一定時間後（_holdDuration）にまとめて
/// cache.markSeen + state クリア + バッジ再計算する。
///
/// 「上の通知ハイライトが消えた後、下にスクロールして未表示通知がハイライト
/// される」という旧挙動を避け、タブを開いた時点での未読を全部まとめて
/// 同じタイミングでハイライト・既読化する仕様。
class NotificationHighlightNotifier extends StateNotifier<Set<String>> {
  NotificationHighlightNotifier(this._ref) : super(const {});

  final Ref _ref;
  static const _holdDuration = Duration(seconds: 5);

  /// アカウント単位の遅延既読化タイマー（連打されてもキャンセル＆上書き）
  final Map<String, Timer> _timers = {};

  /// アカウント単位の対象通知（10 秒経過後にまとめて markSeen するため保持）
  final Map<String, List<String>> _pendingByAccount = {};

  /// 指定アカウントの未読通知をハイライトに登録 → 10 秒後にまとめて既読化。
  /// 既に同じアカウントのタイマーが走っている場合はリセットして上書きする。
  void activateForAccount(String accountId) {
    final cache = NotificationCacheService.instance;
    final unread = [
      for (final n in cache.get(accountId))
        if (cache.isNew(n)) n,
    ];
    if (unread.isEmpty) return;

    final ids = unread.map((n) => n.id).toSet();
    state = {...state, ...ids};
    _pendingByAccount[accountId] = ids.toList();
    _timers[accountId]?.cancel();
    _timers[accountId] = Timer(_holdDuration, () => _flush(accountId));
  }

  /// タイマー満了時に呼ばれ、対象通知を一括 markSeen → ハイライト解除 → バッジ再計算。
  void _flush(String accountId) {
    final pending = _pendingByAccount.remove(accountId);
    _timers.remove(accountId);
    if (pending == null || pending.isEmpty) return;
    final cache = NotificationCacheService.instance;
    for (final n in cache.get(accountId)) {
      if (pending.contains(n.id)) {
        cache.markSeen(n);
      }
    }
    state = state.where((id) => !pending.contains(id)).toSet();

    // バッジ件数の再計算
    final accountIds = AccountStorageService.instance.accounts
        .where((a) => a.isEnabled)
        .map((a) => a.id)
        .toList();
    _ref.read(notificationBadgeProvider.notifier).refreshBadge(accountIds);
  }

  bool isHighlighted(String notificationId) =>
      state.contains(notificationId);

  @override
  void dispose() {
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    _pendingByAccount.clear();
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

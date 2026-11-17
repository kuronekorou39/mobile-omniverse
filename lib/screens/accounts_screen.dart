import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/account.dart';
import '../models/sns_service.dart';
import '../providers/account_provider.dart';
import '../providers/fetch_status_provider.dart';
import '../providers/settings_provider.dart';
import '../services/onboarding_service.dart';
import '../services/timeline_fetch_scheduler.dart';
import '../utils/app_snackbar.dart';
import '../widgets/empty_state.dart';
import '../widgets/home_rail.dart';
import '../widgets/onboarding/coach_mark.dart';
import '../widgets/onboarding/onboarding_dialog.dart';
import '../widgets/onboarding/onboarding_trigger.dart';
import '../widgets/sns_badge.dart';
import 'follow_capture_screen.dart';
import 'follow_target_screen.dart';
import 'likes_bookmarks_screen.dart';
import 'login_webview_screen.dart';
import 'session_refresh_screen.dart';
import 'settings_screen.dart';
import 'user_profile_screen.dart';
import 'user_search_screen.dart';

class AccountsScreen extends ConsumerStatefulWidget {
  const AccountsScreen({super.key});

  @override
  ConsumerState<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends ConsumerState<AccountsScreen> {
  final _addButtonKey = GlobalKey();

  /// 初回起動のようこそ。続けて「アカウント追加」ボタンを指して誘導する
  Future<void> _showWelcome(BuildContext context) async {
    await showOnboardingDialog(
      context,
      icon: Icons.waving_hand_outlined,
      title: 'OmniVerse へようこそ',
      lead: 'X と Bluesky を、ひとつのアプリでまとめて使えます。',
      items: const [
        (
          icon: Icons.view_stream_outlined,
          title: 'タイムラインをひとつに',
          body: '追加したアカウントのタイムラインを、まとめて 1 本で読めます。',
        ),
        (
          icon: Icons.notifications_outlined,
          title: '通知もまとめて',
          body: 'アカウントごとの通知を 1 か所で確認できます。',
        ),
        (
          icon: Icons.edit_outlined,
          title: '同時に投稿',
          body: '複数のアカウントに、同じ内容をまとめて投稿できます。',
        ),
      ],
      buttonLabel: 'はじめる',
    );
    if (!mounted || !context.mounted) return;
    await showCoachMark(
      context,
      targetKey: _addButtonKey,
      title: 'まずはアカウントを追加',
      message: 'ここを押して X か Bluesky を選び、いつものようにログインします。',
      // 案内の部品はアカウントが増えると消えるので、画面自身の context で進める
      onTargetTap: () => _showAddAccountDialog(this.context, ref),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountProvider);

    // ホームが左の列を出しているときは、ヘッダーのボタンはそちらにある
    final railActive = HomeRailScope.isActive(context);

    return Scaffold(
      appBar: railActive ? null : AppBar(
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
                      // アカウントが無いうちは走査対象も無いので出さない
                      if (accounts.isNotEmpty) ...[
                        IconButton(
                          icon: const Icon(Icons.groups_outlined, size: 20),
                          tooltip: 'フォロー / フォロワー',
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const FollowCaptureScreen()),
                          ),
                          constraints:
                              const BoxConstraints(minWidth: 40, minHeight: 40),
                          padding: EdgeInsets.zero,
                        ),
                        IconButton(
                          icon: const Icon(Icons.person_search, size: 20),
                          tooltip: 'ユーザー検索',
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const UserSearchScreen()),
                          ),
                          constraints:
                              const BoxConstraints(minWidth: 40, minHeight: 40),
                          padding: EdgeInsets.zero,
                        ),
                      ],
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
      body: accounts.isEmpty
          ? OnboardingTrigger(
              step: OnboardingStep.welcome,
              when: () => ref.read(accountProvider).isEmpty,
              show: _showWelcome,
              child: EmptyState(
                icon: Icons.person_add,
                title: 'アカウント未登録',
                subtitle: 'SNS アカウントを追加して\nタイムラインを取得しましょう',
                action: FilledButton.icon(
                  key: _addButtonKey,
                  onPressed: () => _showAddAccountDialog(context, ref),
                  icon: const Icon(Icons.add),
                  label: const Text('アカウント追加'),
                ),
              ),
            )
          : SafeArea(
              bottom: false,
              child: Column(
              children: [
                // 全ON/OFF
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
                  child: Row(
                    children: [
                      // つまみを置かないぶん、動かし方を言葉で添える
                      Expanded(
                        child: Text(
                          '長押しで並び替え',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant
                                .withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => ref.read(accountProvider.notifier).enableAll(),
                        style: TextButton.styleFrom(
                          minimumSize: Size.zero,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('全ON'),
                      ),
                      TextButton(
                        onPressed: () => ref.read(accountProvider.notifier).disableAll(),
                        style: TextButton.styleFrom(
                          minimumSize: Size.zero,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          foregroundColor: Colors.grey,
                        ),
                        child: const Text('全OFF'),
                      ),
                    ],
                  ),
                ),
                // アカウントのカード + 追加ボタン
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: _accountCardMaxSide,
                      mainAxisSpacing: _accountCardGap,
                      crossAxisSpacing: _accountCardGap,
                    ),
                    itemCount: accounts.length + 1,
                    itemBuilder: (context, index) {
                      if (index == accounts.length) {
                        return _AddAccountCard(
                          onTap: () => _showAddAccountDialog(context, ref),
                        );
                      }
                      return _AccountCard(
                        key: ValueKey(accounts[index].id),
                        account: accounts[index],
                        index: index,
                      );
                    },
                  ),
                ),
              ],
            ),
            ),
    );
  }

  void _showAddAccountDialog(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'SNS を選択',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            for (final service in SnsService.values)
              ListTile(
                leading: Icon(
                  service == SnsService.x ? Icons.close : Icons.cloud,
                ),
                title: Text(service.label),
                subtitle: Text(service.domain),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _openLogin(context, ref, service);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _openLogin(
      BuildContext context, WidgetRef ref, SnsService service) async {
    final result = await Navigator.of(context).push<LoginResult>(
      MaterialPageRoute(
        builder: (_) => LoginWebViewScreen(service: service),
      ),
    );

    if (result == null) return;

    // 同じサービス+ハンドルのアカウントが既に存在するかチェック
    final existing = ref.read(accountProvider);
    final duplicate = existing.any((a) =>
        a.service == result.service &&
        a.handle.toLowerCase() == result.handle.toLowerCase());
    if (duplicate) {
      if (context.mounted) {
        showAppSnackBar(context, '${result.handle} は既に追加されています', type: SnackType.warning);
      }
      return;
    }

    final account = Account(
      id: '${service.name}_${DateTime.now().millisecondsSinceEpoch}',
      service: service,
      displayName: result.displayName,
      handle: result.handle,
      avatarUrl: result.avatarUrl,
      credentials: result.credentials,
      createdAt: DateTime.now(),
      isProtected: result.isProtected,
    );

    await ref.read(accountProvider.notifier).addAccount(account);

    // アカウント追加時にフェッチが停止中なら自動開始
    final settings = ref.read(settingsProvider);
    if (!settings.isFetchingActive) {
      ref.read(settingsProvider.notifier).startFetching();
    }

  }
}

/// カード 1 枚の辺の上限。スマホの縦で 2 列になる大きさ
const _accountCardMaxSide = 220.0;
const _accountCardGap = 12.0;
const _accountCardRadius = 20.0;

/// アカウント 1 件を表す正方形のカード。
///
/// タップで詳細、右上のスイッチで取得の ON/OFF、長押しして別のカードへ
/// 運ぶと並び替え。
class _AccountCard extends ConsumerWidget {
  const _AccountCard({super.key, required this.account, required this.index});

  final Account account;
  final int index;

  /// 異常時だけ色を返す。正常・不明はドットを出さない
  /// （常に緑が点いていると、それが普通になって異常に気づきにくい）
  static Color? _healthColor(AccountHealth health) => switch (health) {
        AccountHealth.warning => Colors.orange,
        AccountHealth.error => Colors.red,
        AccountHealth.good || AccountHealth.unknown => null,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.maxWidth;
        final card = _buildCard(context, ref, side);
        return DragTarget<int>(
          onWillAcceptWithDetails: (details) => details.data != index,
          onAcceptWithDetails: (details) {
            final from = details.data;
            // reorder は「抜く前の並びでの差し込み位置」を取る
            ref
                .read(accountProvider.notifier)
                .reorder(from, from < index ? index + 1 : index);
          },
          builder: (context, candidates, _) {
            final scheme = Theme.of(context).colorScheme;
            return LongPressDraggable<int>(
              data: index,
              feedback: Opacity(
                opacity: 0.9,
                child: SizedBox.square(dimension: side, child: card),
              ),
              childWhenDragging: Opacity(opacity: 0.3, child: card),
              // 運ばれてきたカードが上にある間は、落とす先を枠で示す
              child: DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(_accountCardRadius),
                  border: candidates.isEmpty
                      ? null
                      : Border.all(color: scheme.primary, width: 2),
                ),
                child: card,
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildCard(BuildContext context, WidgetRef ref, double side) {
    final scheme = Theme.of(context).colorScheme;
    final status = ref.watch(fetchStatusProvider)[account.id];
    final health = account.isEnabled
        ? (status?.health ?? AccountHealth.unknown)
        : AccountHealth.unknown;
    final healthColor = _healthColor(health);
    final avatarRadius = side * 0.2;

    return Material(
      color: scheme.surfaceContainer,
      borderRadius: BorderRadius.circular(_accountCardRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openDetail(context),
        child: Stack(
          children: [
            // OFF のアカウントは沈めて、取得していないことを見た目で伝える
            Positioned.fill(
              child: Opacity(
                opacity: account.isEnabled ? 1 : 0.45,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(height: side * 0.12),
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          CircleAvatar(
                            radius: avatarRadius,
                            backgroundImage: account.avatarUrl != null
                                ? NetworkImage(account.avatarUrl!)
                                : null,
                            child: account.avatarUrl == null
                                ? Text(
                                    account.displayName.isNotEmpty
                                        ? account.displayName[0].toUpperCase()
                                        : '?',
                                    style:
                                        TextStyle(fontSize: avatarRadius * 0.8),
                                  )
                                : null,
                          ),
                          // 正常なときは出さない。異常だけが目に入るようにする
                          if (healthColor != null)
                            Positioned(
                              left: 0,
                              bottom: 0,
                              child: Container(
                                width: 14,
                                height: 14,
                                decoration: BoxDecoration(
                                  color: healthColor,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: scheme.surfaceContainer,
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      SizedBox(height: side * 0.06),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(
                              account.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (account.isProtected) ...[
                            const SizedBox(width: 3),
                            Icon(Icons.lock,
                                size: 13, color: scheme.onSurfaceVariant),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        account.handle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // タイムラインのカードと同じく、サービスのバッジは左上に置く
            Positioned(
              top: 12,
              left: 12,
              child: SnsBadge(service: account.service, size: 12),
            ),
            Positioned(
              top: 0,
              right: 2,
              child: Transform.scale(
                scale: 0.8,
                alignment: Alignment.topRight,
                child: Switch(
                  value: account.isEnabled,
                  onChanged: (_) {
                    ref
                        .read(accountProvider.notifier)
                        .toggleAccount(account.id);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openDetail(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _AccountDetailScreen(accountId: account.id),
      ),
    );
  }
}

/// 並びの最後に置く「追加」のカード。面を塗らず枠だけにして、
/// 既にあるアカウントと見分けが付くようにする
class _AddAccountCard extends StatelessWidget {
  const _AddAccountCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_accountCardRadius),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final side = constraints.maxWidth;
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add, size: side * 0.3, color: scheme.primary),
                SizedBox(height: side * 0.04),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'アカウントを追加',
                      maxLines: 1,
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// アカウント詳細画面
class _AccountDetailScreen extends ConsumerStatefulWidget {
  const _AccountDetailScreen({required this.accountId});

  final String accountId;

  @override
  ConsumerState<_AccountDetailScreen> createState() =>
      _AccountDetailScreenState();
}

class _AccountDetailScreenState extends ConsumerState<_AccountDetailScreen> {
  // 初回の案内で明るくする場所
  final _viewKey = GlobalKey();
  final _connectionsKey = GlobalKey();
  final _settingsKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _maybeShowTour();
  }

  /// 初めて開いたときに、この画面でできることを場所を指しながら順に説明する
  void _maybeShowTour() {
    const step = OnboardingStep.accountDetail;
    if (!OnboardingService.instance.shouldShow(step)) return;
    // 画面遷移のアニメーションが終わってから
    Future.delayed(const Duration(milliseconds: 450), () {
      if (!mounted || !OnboardingService.instance.shouldShow(step)) return;
      OnboardingService.instance.markSeen(step);
      showCoachMarkTour(context, steps: [
        CoachMarkStep(
          targetKey: _viewKey,
          title: 'このアカウントの投稿を見る',
          message: 'プロフィールや、いいね・ブックマークした投稿の一覧を開けます。',
        ),
        CoachMarkStep(
          targetKey: _connectionsKey,
          title: 'つながりを調べる',
          message: 'フォロー / フォロワーの一覧を取り込んで、相互かどうかや前回からの増減を確かめられます。',
        ),
        CoachMarkStep(
          targetKey: _settingsKey,
          title: 'このアカウントの設定',
          message: 'タイムラインに読み込むかどうかと、フォロー先の RT を隠すかを切り替えます。',
        ),
      ]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountProvider);
    final account =
        accounts.where((a) => a.id == widget.accountId).firstOrNull;

    if (account == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('アカウント')),
        body: const Center(child: Text('アカウントが見つかりません')),
      );
    }

    final scheme = Theme.of(context).colorScheme;

    final profile = <Widget>[
      // プロフィールヘッダー。中央揃えで縦に積むと 80dp 以上使うので、
      // 横 1 行にして情報の密度を上げる
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: scheme.primaryContainer,
              backgroundImage: account.avatarUrl != null
                  ? NetworkImage(account.avatarUrl!)
                  : null,
              child: account.avatarUrl == null
                  ? Text(
                      account.displayName.isNotEmpty
                          ? account.displayName[0].toUpperCase()
                          : '?',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: scheme.onPrimaryContainer,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          account.displayName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (account.isProtected) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.lock,
                            size: 16, color: scheme.onSurfaceVariant),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      SnsBadge(service: account.service),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          account.handle,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 14,
                              color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                  _SessionChip(
                    accountId: account.id,
                    onTap: () =>
                        _openSessionRefresh(context, ref, account),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ];
    final viewCard = <Widget>[
      // 「見るもの」はひとつの面にまとめる。同じ重さの行が並ぶので
      // カード 1 枚に収め、区切り線だけで分ける
      Padding(
        key: _viewKey,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
          child: Column(
            children: [
              _NavRow(
                icon: Icons.person_outline,
                label: 'プロフィール',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => UserProfileScreen(
                      username: account.displayName,
                      handle: account.handle,
                      service: account.service,
                      avatarUrl: account.avatarUrl,
                      accountId: account.id,
                    ),
                  ),
                ),
              ),
              const _NavDivider(),
              _NavRow(
                icon: Icons.favorite_border,
                label: 'ふぁぼ',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => LikesBookmarksScreen(
                        account: account, initialIndex: 0),
                  ),
                ),
              ),
              const _NavDivider(),
              _NavRow(
                icon: Icons.bookmark_border,
                label: 'ブックマーク',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => LikesBookmarksScreen(
                        account: account, initialIndex: 1),
                  ),
                ),
              ),
              const _NavDivider(),
            ],
          ),
        ),
      ),
    ];
    final connections = <Widget>[
      // 収集を伴う重い機能なので、面と枠を変えて 1 段持ち上げる。
      // 遷移先の「つながり調査」と語がぶつからないよう動詞にした
      Padding(
        key: _connectionsKey,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Material(
          color: scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => FollowTargetScreen(
                  service: account.service,
                  handle:
                      account.handle.replaceFirst('@', '').toLowerCase(),
                ),
              ),
            ),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: scheme.primary, width: 1.5),
                borderRadius: BorderRadius.circular(18),
              ),
              padding:
                  const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
              child: Row(
                children: [
                  Icon(Icons.groups_outlined,
                      size: 28, color: scheme.primary),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('つながりを調べる',
                            style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(
                          'フォロー / フォロワーの一覧・相互の判定・差分',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right,
                      size: 22, color: scheme.primary),
                ],
              ),
            ),
          ),
        ),
      ),
    ];
    final settingRows = <Widget>[
      // 設定は面を持たせず、入口より一段軽くする。見出しは付けない
      // （2 行しかなく、面の違いで入口とは区別がつく）
      Column(
        key: _settingsKey,
        children: [
          _SettingRow(
            label: 'タイムライン取得',
            value: account.isEnabled,
            onChanged: (_) => ref
                .read(accountProvider.notifier)
                .toggleAccount(account.id),
          ),
          _SettingRow(
            label: 'フォロー先の RT を非表示',
            value: ref
                .watch(settingsProvider)
                .hideRetweetsAccountIds
                .contains(account.id),
            onChanged: (_) => ref
                .read(settingsProvider.notifier)
                .toggleHideRetweets(account.id),
          ),
        ],
      ),
    ];
    final danger = <Widget>[
      // 破壊的操作はフォールドの下へ。消えるのはこのアプリの登録と
      // 保存データで、SNS 側のアカウントではない。何が消えるかは
      // 確認ダイアログで伝える
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 10),
        child: Divider(height: 1, color: scheme.outlineVariant),
      ),
      InkWell(
        onTap: () => _confirmDelete(context, ref, account),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 22, color: scheme.error),
              const SizedBox(width: 14),
              Text('アカウント一覧から削除',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: scheme.error)),
            ],
          ),
        ),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        // 更新と削除はここから外した。更新は期限切れチップから、削除は
        // 破壊的操作なので最下部に置く
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'refresh') _openSessionRefresh(context, ref, account);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'refresh', child: Text('セッションを更新')),
            ],
          ),
        ],
      ),
      // 横に広い画面は縦が狭いので、このアカウントのこと（名前・設定・削除）と
      // 開く先（投稿・つながり）を左右に分けて、スクロールせずに収める
      body: WideColumns(
        padding: const EdgeInsets.only(bottom: 32),
        single: [
          ...profile,
          ...viewCard,
          const SizedBox(height: 22),
          ...connections,
          const SizedBox(height: 18),
          ...settingRows,
          ...danger,
        ],
        first: [...profile, ...settingRows, ...danger],
        second: [
          const SizedBox(height: 4),
          ...viewCard,
          const SizedBox(height: 16),
          ...connections,
        ],
      ),
    );
  }

  Future<void> _openSessionRefresh(
      BuildContext context, WidgetRef ref, Account account) async {
    final result = await Navigator.of(context).push<SessionRefreshResult>(
      MaterialPageRoute(
        builder: (_) => SessionRefreshScreen(account: account),
      ),
    );

    if (result == null) return;

    // 更新前の値を記録
    final oldCreds = account.service == SnsService.x ? account.xCredentials : null;
    final oldCt0 = oldCreds?.ct0 ?? '';
    final oldCookieLen = oldCreds?.allCookies.length ?? 0;

    await ref
        .read(accountProvider.notifier)
        .updateCredentials(account.id, result.credentials);

    // スケジューラの期限切れ状態をクリア → 次回フェッチで再試行
    TimelineFetchScheduler.instance.clearExpiredState(account.id);

    // 更新後の値を取得
    String detail = '';
    if (result.credentials is XCredentials) {
      final newCreds = result.credentials as XCredentials;
      final ct0Changed = oldCt0 != newCreds.ct0;
      detail = '\nct0: ${ct0Changed ? "変更あり" : "変更なし"}'
          ' (${newCreds.ct0.length > 8 ? newCreds.ct0.substring(0, 8) : newCreds.ct0}...)'
          '\ncookies: ${newCreds.allCookies.length} chars'
          '${oldCookieLen != newCreds.allCookies.length ? " (前: $oldCookieLen)" : ""}';
    }

    if (context.mounted) {
      showAppSnackBar(context, 'セッションを更新しました$detail', type: SnackType.success, duration: const Duration(seconds: 5));
    }
  }

  void _confirmDelete(
      BuildContext context, WidgetRef ref, Account account) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('アカウント一覧から削除'),
        // SNS 側のアカウントは消えない。消えるのはこのアプリの登録と、
        // そのアカウントで集めた保存データ
        content: Text('${account.displayName} (${account.handle}) を'
            'アプリから削除します。\n\n'
            'このアカウントで保存したデータもすべて消えます。'
            'X / Bluesky 側のアカウントはそのままです。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ref.read(accountProvider.notifier).removeAccount(account.id);
              Navigator.of(context).pop(); // 詳細画面を閉じる
            },
            child: const Text('削除'),
          ),
        ],
      ),
    );
  }
}

/// 入口リストの 1 行。すべて同じ重さで並ぶので、面はまとめて親が持つ
class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 8),
        child: Row(
          children: [
            Icon(icon, size: 22, color: scheme.primary),
            const SizedBox(width: 14),
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w500)),
            ),
            Icon(Icons.chevron_right,
                size: 20, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// 行間の区切り。アイコンぶんだけ左を空けて、テキストの頭に揃える
class _NavDivider extends StatelessWidget {
  const _NavDivider();

  @override
  Widget build(BuildContext context) => Container(
        height: 1,
        margin: const EdgeInsets.only(left: 44),
        color: Theme.of(context).colorScheme.outlineVariant,
      );
}

/// 設定の 1 行。面を持たせず、入口リストより軽く見せる
class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 24),
        child: Row(
          children: [
            Expanded(
              child: Text(label, style: const TextStyle(fontSize: 15)),
            ),
            const SizedBox(width: 14),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      );
}

/// トークンが切れているときだけ出る。押すとセッション更新へ。
///
/// 以前は起動時のスナックバー 1 回きりで、見逃すと取得が全部失敗して
/// いることに気づけなかった。切れている間はここに出し続ける。
class _SessionChip extends StatelessWidget {
  const _SessionChip({required this.accountId, required this.onTap});

  final String accountId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<Set<String>>(
      valueListenable: TimelineFetchScheduler.instance.expiredAccountIds,
      builder: (context, expired, _) {
        if (!expired.contains(accountId)) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Material(
            color: scheme.errorContainer,
            borderRadius: BorderRadius.circular(9),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(9),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 7, 12, 7),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.refresh,
                        size: 17, color: scheme.onErrorContainer),
                    const SizedBox(width: 6),
                    Text(
                      '要再ログイン・セッションを更新',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: scheme.onErrorContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

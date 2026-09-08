import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/account.dart';
import '../models/follow_user.dart';
import '../models/sns_service.dart';
import '../providers/account_provider.dart';
import '../services/user_search_service.dart';
import '../widgets/empty_state.dart';
import '../widgets/sns_badge.dart';
import 'user_profile_screen.dart';

/// ユーザーを探して、プロフィールを開くための画面
///
/// どのアカウントの資格情報で探すかによって、探せる範囲が変わる。
/// X はハンドル完全一致だけ、Bluesky は表示名やプロフィール文も引っかかる。
class UserSearchScreen extends ConsumerStatefulWidget {
  const UserSearchScreen({super.key});

  @override
  ConsumerState<UserSearchScreen> createState() => _UserSearchScreenState();
}

class _UserSearchScreenState extends ConsumerState<UserSearchScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  String? _accountId;
  List<FollowUser>? _results;
  bool _isSearching = false;
  String? _error;

  /// 結果がどの条件で得られたか。あとから条件を変えても表示は結果に従う
  String _searchedQuery = '';

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Account? _selectedAccount(List<Account> accounts) {
    if (accounts.isEmpty) return null;
    return accounts.firstWhere(
      (a) => a.id == _accountId,
      orElse: () => accounts.first,
    );
  }

  Future<void> _search(Account account) async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;

    _focus.unfocus();
    setState(() {
      _isSearching = true;
      _error = null;
      _searchedQuery = query;
    });

    try {
      final users = await UserSearchService.instance.search(account, query);
      if (!mounted) return;
      setState(() {
        _results = users;
        _isSearching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _isSearching = false;
      });
    }
  }

  void _openProfile(Account account, FollowUser user) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UserProfileScreen(
          username: user.name.isEmpty ? user.screenName : user.name,
          handle: user.screenName,
          service: account.service,
          avatarUrl: user.avatarUrl.isEmpty ? null : user.avatarUrl,
          accountId: account.id,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accounts =
        ref.watch(accountProvider).where((a) => a.isEnabled).toList();
    final account = _selectedAccount(accounts);

    return Scaffold(
      appBar: AppBar(title: const Text('ユーザー検索')),
      body: account == null
          ? const EmptyState(
              icon: Icons.person_search,
              title: 'アカウントがありません',
              subtitle: '検索は登録済みのアカウントの資格情報で行います',
            )
          : Column(
              children: [
                if (accounts.length > 1)
                  _AccountSelector(
                    accounts: accounts,
                    selectedId: account.id,
                    onSelect: (id) => setState(() {
                      _accountId = id;
                      // 探せる範囲が変わるので、前の結果は持ち越さない
                      _results = null;
                      _error = null;
                    }),
                  ),
                _SearchField(
                  controller: _controller,
                  focusNode: _focus,
                  service: account.service,
                  isSearching: _isSearching,
                  onSubmit: () => _search(account),
                ),
                const Divider(height: 1),
                Expanded(child: _buildBody(account)),
              ],
            ),
    );
  }

  Widget _buildBody(Account account) {
    if (_isSearching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return EmptyState(
        icon: Icons.error_outline,
        title: '検索できませんでした',
        subtitle: _error,
      );
    }

    final results = _results;
    if (results == null) {
      return EmptyState(
        icon: Icons.person_search,
        title: account.service == SnsService.x ? '@ID を入れて検索' : 'ユーザーを検索',
        subtitle: account.service == SnsService.x
            ? 'X は ID の完全一致でしか探せません。\nプロフィールの URL を貼っても構いません'
            : 'ハンドル・表示名・プロフィール文から探します',
      );
    }
    if (results.isEmpty) {
      return EmptyState(
        icon: Icons.search_off,
        title: '「$_searchedQuery」は見つかりません',
        subtitle: account.service == SnsService.x
            ? 'ID が違うか、凍結・削除された可能性があります'
            : null,
      );
    }

    return ListView.separated(
      itemCount: results.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
      itemBuilder: (context, index) => _UserResultTile(
        user: results[index],
        service: account.service,
        onTap: () => _openProfile(account, results[index]),
      ),
    );
  }
}

/// どのアカウントで探すか
class _AccountSelector extends StatelessWidget {
  const _AccountSelector({
    required this.accounts,
    required this.selectedId,
    required this.onSelect,
  });

  final List<Account> accounts;
  final String selectedId;
  final void Function(String id) onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: accounts.length,
        itemBuilder: (context, index) {
          final account = accounts[index];
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              selected: account.id == selectedId,
              onSelected: (_) => onSelect(account.id),
              avatar: SnsBadge(service: account.service, size: 9),
              label: Text(account.handle),
              labelStyle: const TextStyle(fontSize: 12),
            ),
          );
        },
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.service,
    required this.isSearching,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final SnsService service;
  final bool isSearching;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        autofocus: true,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => onSubmit(),
        decoration: InputDecoration(
          hintText: service == SnsService.x ? '@ID を入れる' : 'ハンドル・名前で探す',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: IconButton(
            icon: const Icon(Icons.arrow_forward),
            tooltip: '検索',
            onPressed: isSearching ? null : onSubmit,
          ),
          isDense: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
      ),
    );
  }
}

class _UserResultTile extends StatelessWidget {
  const _UserResultTile({
    required this.user,
    required this.service,
    required this.onTap,
  });

  final FollowUser user;
  final SnsService service;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: scheme.surfaceContainerHighest,
        backgroundImage:
            user.avatarUrl.isEmpty ? null : NetworkImage(user.avatarUrl),
        child: user.avatarUrl.isEmpty
            ? Icon(Icons.person, color: scheme.onSurfaceVariant)
            : null,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              user.name.isEmpty ? user.screenName : user.name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          if (user.isProtected) ...[
            const SizedBox(width: 4),
            Icon(Icons.lock_outline, size: 14, color: scheme.onSurfaceVariant),
          ],
          const SizedBox(width: 6),
          SnsBadge(service: service, size: 9),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('@${user.screenName}',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          if (user.description.isNotEmpty)
            Text(
              user.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
        ],
      ),
      isThreeLine: user.description.isNotEmpty,
    );
  }
}

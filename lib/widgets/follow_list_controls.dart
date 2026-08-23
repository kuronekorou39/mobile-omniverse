import 'dart:async';

import 'package:flutter/material.dart';

import '../services/follow_db.dart';

/// フォロー/フォロワー系の一覧の上に置く「絞り込み + 並び替え」。
///
/// 一覧・相互・差分の 3 画面で同じものを使う。並び替えは「何で並べるか」と
/// 「昇順か降順か」を別々に選ばせる（1 つの列挙にすると項目が掛け算で増え、
/// 欲しい組み合わせが無い、という状態になりやすい）。
class FollowListControls extends StatefulWidget {
  const FollowListControls({
    super.key,
    required this.filter,
    required this.sort,
    required this.onChanged,
    this.showProtected = true,
    this.showSort = true,
  });

  final FollowFilter filter;
  final FollowSort sort;
  final void Function(FollowFilter filter, FollowSort sort) onChanged;

  /// Bluesky に鍵アカウントの概念は無いので、その場合は出さない
  final bool showProtected;

  /// 並びが固定の画面（件数の変化）では隠す
  final bool showSort;

  @override
  State<FollowListControls> createState() => _FollowListControlsState();
}

class _FollowListControlsState extends State<FollowListControls> {
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    // 1 文字ごとに数万件を数え直すと重いので、少し置いてから流す
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      widget.onChanged(widget.filter.copyWith(search: value), widget.sort);
    });
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.filter.activeCount;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        children: [
          TextField(
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search, size: 20),
              hintText: '@ID・名前で絞り込み',
              border: OutlineInputBorder(),
            ),
            onChanged: _onSearchChanged,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              if (widget.showSort)
                Expanded(
                  child: OutlinedButton.icon(
                    icon: Icon(
                        widget.sort.descending
                            ? Icons.arrow_downward
                            : Icons.arrow_upward,
                        size: 16),
                    label: Text(widget.sort.label,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12)),
                    onPressed: _openSortSheet,
                  ),
                ),
              if (widget.showSort) const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: Icon(
                      active == 0
                          ? Icons.filter_list
                          : Icons.filter_list_alt,
                      size: 16),
                  label: Text(active == 0 ? '絞り込み' : '絞り込み ($active)',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12)),
                  onPressed: _openFilterSheet,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openSortSheet() async {
    var sort = widget.sort;
    final picked = await showModalBottomSheet<FollowSort>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text('並び替え',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    for (final desc in const [true, false])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(sort.key.directionLabel(desc)),
                          selected: sort.descending == desc,
                          onSelected: (_) =>
                              setLocal(() => sort = sort.withDirection(desc)),
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(),
              for (final key in FollowSortKey.values)
                ListTile(
                  dense: true,
                  title: Text(key.label),
                  trailing: sort.key == key
                      ? const Icon(Icons.check, size: 20)
                      : null,
                  onTap: () => setLocal(() => sort = sort.withKey(key)),
                ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx, sort),
                  child: const Text('この順で並べる'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) widget.onChanged(widget.filter, picked);
  }

  Future<void> _openFilterSheet() async {
    var filter = widget.filter;
    final picked = await showModalBottomSheet<FollowFilter>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text('絞り込み',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              if (widget.showProtected)
                _tristate(
                  label: '鍵アカウント',
                  value: filter.protected,
                  onLabel: '鍵のみ',
                  offLabel: '鍵を除く',
                  onChanged: (v) => setLocal(() => filter = FollowFilter(
                        search: filter.search,
                        protected: v,
                        verified: filter.verified,
                      )),
                ),
              _tristate(
                label: '認証済み',
                value: filter.verified,
                onLabel: '認証のみ',
                offLabel: '認証を除く',
                onChanged: (v) => setLocal(() => filter = FollowFilter(
                      search: filter.search,
                      protected: filter.protected,
                      verified: v,
                    )),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(
                            ctx, FollowFilter(search: filter.search)),
                        child: const Text('条件を外す'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(ctx, filter),
                        child: const Text('この条件で絞る'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) widget.onChanged(picked, widget.sort);
  }

  /// 「指定なし / 該当のみ / 該当を除く」の 3 択
  Widget _tristate({
    required String label,
    required bool? value,
    required String onLabel,
    required String offLabel,
    required ValueChanged<bool?> onChanged,
  }) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                for (final choice in <(String, bool?)>[
                  ('指定なし', null),
                  (onLabel, true),
                  (offLabel, false),
                ])
                  ChoiceChip(
                    label: Text(choice.$1),
                    selected: value == choice.$2,
                    onSelected: (_) => onChanged(choice.$2),
                  ),
              ],
            ),
          ],
        ),
      );
}

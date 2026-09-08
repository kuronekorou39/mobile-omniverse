import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/account.dart';
import '../models/sns_service.dart';
import '../providers/account_provider.dart';
import '../services/shadowban_check_service.dart';
import '../widgets/empty_state.dart';

/// X のアカウントに「表示されにくくなるフラグ」が付いていないかを見る画面
///
/// 出せるのは症状の有無だけ。「シャドウバンされていない」とは言えないので、
/// 画面の文言でも判定っぽく見せない。
class ShadowbanCheckScreen extends ConsumerStatefulWidget {
  const ShadowbanCheckScreen({super.key, required this.screenName});

  /// 調べる相手の ID（@ は付いていてもいなくてもよい）
  final String screenName;

  @override
  ConsumerState<ShadowbanCheckScreen> createState() =>
      _ShadowbanCheckScreenState();
}

class _ShadowbanCheckScreenState extends ConsumerState<ShadowbanCheckScreen> {
  String? _accountId;
  ShadowbanReport? _report;
  bool _isChecking = false;

  Account? _selected(List<Account> accounts) {
    if (accounts.isEmpty) return null;
    return accounts.firstWhere(
      (a) => a.id == _accountId,
      orElse: () => accounts.first,
    );
  }

  Future<void> _run(Account by) async {
    setState(() => _isChecking = true);
    final report =
        await ShadowbanCheckService.instance.check(by, widget.screenName);
    if (!mounted) return;
    setState(() {
      _report = report;
      _isChecking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountProvider)
        .where((a) => a.isEnabled && a.service == SnsService.x)
        .toList();
    final account = _selected(accounts);
    final target = widget.screenName.replaceFirst(RegExp(r'^@+'), '');

    return Scaffold(
      appBar: AppBar(title: const Text('表示制限の確認')),
      body: account == null
          ? const EmptyState(
              icon: Icons.person_off_outlined,
              title: 'X のアカウントがありません',
              subtitle: '確認には X のアカウントの資格情報が要ります',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                Text('@$target',
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w600)),
                const SizedBox(height: 16),
                _AccountPicker(
                  accounts: accounts,
                  selectedId: account.id,
                  targetScreenName: target,
                  onSelect: (id) => setState(() {
                    _accountId = id;
                    _report = null;
                  }),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _isChecking ? null : () => _run(account),
                  icon: _isChecking
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search),
                  label: Text(_report == null ? '確認する' : 'もう一度確認する'),
                ),
                const SizedBox(height: 24),
                if (_report != null) ...[
                  _ReportView(report: _report!),
                  const SizedBox(height: 24),
                ],
                const _Caveats(),
              ],
            ),
    );
  }
}

class _AccountPicker extends StatelessWidget {
  const _AccountPicker({
    required this.accounts,
    required this.selectedId,
    required this.targetScreenName,
    required this.onSelect,
  });

  final List<Account> accounts;
  final String selectedId;
  final String targetScreenName;
  final void Function(String id) onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('どのアカウントで見に行くか',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: accounts.map((a) {
            final bare = a.handle.replaceFirst(RegExp(r'^@+'), '');
            final isSelf =
                bare.toLowerCase() == targetScreenName.toLowerCase();
            return ChoiceChip(
              selected: a.id == selectedId,
              onSelected: (_) => onSelect(a.id),
              label: Text(isSelf ? '$bare（本人）' : bare),
              labelStyle: const TextStyle(fontSize: 12),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _ReportView extends StatelessWidget {
  const _ReportView({required this.report});

  final ShadowbanReport report;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (report.hasError) {
      return _Panel(
        color: scheme.errorContainer,
        child: Row(
          children: [
            Icon(Icons.error_outline, size: 20, color: scheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(report.error!,
                  style: TextStyle(color: scheme.onErrorContainer)),
            ),
          ],
        ),
      );
    }

    final flagged = report.flagged;
    final unknownCount = report.findings
        .where((f) => f.verdict == ShadowbanVerdict.unknown)
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Panel(
          color: flagged.isEmpty
              ? scheme.surfaceContainerHighest
              : scheme.tertiaryContainer,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                flagged.isEmpty
                    ? '見えている範囲では、制限を示すフラグは付いていません'
                    : '${flagged.length} 件のフラグが付いています',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                flagged.isEmpty
                    ? 'これは「制限されていない」という意味ではありません。'
                        'ここで見られるのはプロフィールに出るフラグだけです'
                    : 'フラグが付いていても、必ず表示が減っているとは限りません',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
              if (unknownCount > 0) ...[
                const SizedBox(height: 6),
                Text('$unknownCount 件は項目が返らず判定できませんでした',
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant)),
              ],
            ],
          ),
        ),
        if (report.isSelfCheck) ...[
          const SizedBox(height: 8),
          _Panel(
            color: scheme.secondaryContainer,
            child: Text(
              '自分のアカウントで自分を見ています。X の表示制限は本人には'
              'かからない作りなので、別のアカウントで見たほうが正確です',
              style:
                  TextStyle(fontSize: 12, color: scheme.onSecondaryContainer),
            ),
          ),
        ],
        const SizedBox(height: 16),
        ...report.findings.map((f) => _FindingRow(finding: f)),
      ],
    );
  }
}

class _FindingRow extends StatelessWidget {
  const _FindingRow({required this.finding});

  final ShadowbanFinding finding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final (IconData icon, Color color) = switch (finding.verdict) {
      ShadowbanVerdict.flagged => (Icons.flag, scheme.tertiary),
      ShadowbanVerdict.notFlagged => (Icons.check, scheme.primary),
      ShadowbanVerdict.unknown => (Icons.help_outline, scheme.onSurfaceVariant),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(finding.label,
                    style: const TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(finding.detail,
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 何が言えて何が言えないか。畳まずに常に出す
class _Caveats extends StatelessWidget {
  const _Caveats();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const items = [
      '「制限されていない」ことは確かめられません。分かるのは、'
          'プロフィールに出るフラグが付いているかどうかだけです',
      'おすすめやホームタイムラインでの順位下げは、外から見る方法がありません',
      '検索に出るか、リプライが折り畳まれるかの確認は、まだ入っていません',
      'アカウントに付く「仮ラベル」は API から取れません。'
          'X からの通知を確認してください',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('この確認でわかること・わからないこと',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant)),
        const SizedBox(height: 8),
        ...items.map((t) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('・',
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant)),
                  Expanded(
                    child: Text(t,
                        style: TextStyle(
                            fontSize: 12,
                            height: 1.5,
                            color: scheme.onSurfaceVariant)),
                  ),
                ],
              ),
            )),
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.color, required this.child});

  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
        ),
        child: child,
      );
}

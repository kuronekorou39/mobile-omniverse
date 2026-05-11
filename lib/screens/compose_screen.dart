import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../models/account.dart';
import '../models/post.dart';
import '../models/sns_service.dart';
import '../providers/compose_queue_provider.dart';
import '../providers/draft_list_provider.dart';
import '../providers/settings_provider.dart';
import '../services/account_storage_service.dart';
import '../services/draft_service.dart';
import '../services/image_resize_service.dart';
import '../utils/app_snackbar.dart';
import '../utils/image_headers.dart';
import '../widgets/draft_list_sheet.dart';
import '../widgets/image_filter_screen.dart';
import '../widgets/sns_badge.dart';
import 'browser_post_debug_screen.dart';

class ComposeScreen extends ConsumerStatefulWidget {
  const ComposeScreen({
    super.key,
    this.quotedPost,
    this.inReplyToPost,
    this.draft,
    this.restoreFailedAccounts = false,
  });

  final Post? quotedPost;
  final Post? inReplyToPost;

  /// 復元対象の下書き（失敗バナーからの再投稿経路、または下書き一覧から選択）。
  final Draft? draft;

  /// true のとき draft.failedAccountIds に該当するアカウントを初期選択する。
  /// 失敗バナーからの「再投稿」経路でのみ true を渡す。
  final bool restoreFailedAccounts;

  @override
  ConsumerState<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends ConsumerState<ComposeScreen> {
  static const int _maxImages = 4;

  final _textController = TextEditingController();
  final _picker = ImagePicker();

  /// 選択中のアカウント id 集合（複数選択）
  final Set<String> _selectedAccountIds = {};

  /// 添付画像（最大 4 枚）。サイズはアップロード時に必要に応じてリサイズ。
  final List<_PickedImage> _images = [];

  /// 編集中の下書き id（draft 引数で開かれた、または下書き一覧で選んだもの）。
  /// 未保存の変更を下書きに保存するときは、この id があれば更新、無ければ新規。
  String? _currentDraftId;
  String _initialText = '';

  List<Account> get _accounts {
    final all = AccountStorageService.instance.accounts.where((a) => a.isEnabled).toList();
    // 引用リポスト/リプライ時は同じプラットフォームのアカウントのみ表示
    final targetPost = widget.quotedPost ?? widget.inReplyToPost;
    if (targetPost != null) {
      return all.where((a) => a.service == targetPost.source).toList();
    }
    return all;
  }

  List<Account> get _selectedAccounts => [
        for (final a in _accounts)
          if (_selectedAccountIds.contains(a.id)) a,
      ];

  @override
  void initState() {
    super.initState();
    final draft = widget.draft;
    if (draft != null) {
      _textController.text = draft.text;
      _currentDraftId = draft.id;
      _initialText = draft.text;
    }
    if (_accounts.isNotEmpty) {
      // 失敗バナーからの再投稿経路: 失敗したアカウント全部を事前選択
      if (widget.restoreFailedAccounts && draft != null) {
        for (final id in draft.failedAccountIds) {
          if (_accounts.any((a) => a.id == id)) {
            _selectedAccountIds.add(id);
          }
        }
      }
      // 何も選択されていなければ先頭アカウントをデフォルト選択
      if (_selectedAccountIds.isEmpty) {
        _selectedAccountIds.add(_accounts.first.id);
      }
    }
  }

  /// 戻る時に下書き保存を促すべきか（未保存の変更があるか）。
  bool get _hasUnsavedChanges {
    final current = _textController.text.trim();
    final original = _initialText.trim();
    return current.isNotEmpty && current != original;
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  /// 選択中のアカウントの中で最も「緩い」文字数上限を採用する。
  /// 個別アカウントが超過する場合は警告を出して投稿は通すが、
  /// その違反アカウントだけ投稿失敗扱いになる（_postToX / _postToBluesky 側で判定）。
  /// X のみ → 280、Bluesky を含む → 300、無選択 → 300。
  int get _maxLength {
    final selected = _selectedAccounts;
    if (selected.isEmpty) return 300;
    final hasBluesky = selected.any((a) => a.service == SnsService.bluesky);
    return hasBluesky ? 300 : 280;
  }

  int get _remaining => _maxLength - _textController.text.length;

  /// 各アカウントごとの制約違反メッセージを集める。
  /// 違反があっても投稿ボタンは押せるが、該当アカウントは投稿失敗で扱われる。
  List<String> get _violations {
    final list = <String>[];
    final hasX = _selectedAccounts.any((a) => a.service == SnsService.x);
    final hasBluesky =
        _selectedAccounts.any((a) => a.service == SnsService.bluesky);
    final textLen = _textController.text.length;

    if (hasX && textLen > 280) {
      list.add('X: 文字数オーバー ($textLen / 280)');
    }
    if (hasBluesky && textLen > 300) {
      list.add('Bluesky: 文字数オーバー ($textLen / 300)');
    }
    for (var i = 0; i < _images.length; i++) {
      final p = _images[i];
      if (!p.isGif) continue; // 通常画像はリサイズで収まる
      if (hasX && p.sizeBytes > ImageResizeService.xMaxBytes) {
        list.add('X: 画像 ${i + 1} がサイズオーバー (${_mb(p.sizeBytes)} / 5MB)');
      }
      if (hasBluesky && p.sizeBytes > ImageResizeService.blueskyMaxBytes) {
        list.add(
            'Bluesky: 画像 ${i + 1} がサイズオーバー (${_mb(p.sizeBytes)} / 2MB)');
      }
    }
    return list;
  }

  String _mb(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';

  void _post() {
    final accounts = _selectedAccounts;
    final hasContent =
        _textController.text.trim().isNotEmpty || _images.isNotEmpty;
    if (accounts.isEmpty || !hasContent) return;

    final text = _textController.text.trim();
    ref.read(composeQueueProvider.notifier).enqueue(
          text: text,
          accounts: accounts,
          inReplyToPost: widget.inReplyToPost,
          quotedPost: widget.quotedPost,
          images: [for (final p in _images) p.file],
          sourceDraftId: _currentDraftId,
        );
    Navigator.of(context).pop();
  }

  void _toggleAccount(Account account) {
    setState(() {
      if (_selectedAccountIds.contains(account.id)) {
        _selectedAccountIds.remove(account.id);
      } else {
        _selectedAccountIds.add(account.id);
      }
    });
  }

  /// 選択中のアカウントの中に X が含まれていれば true。Phase 5a では X への画像投稿は
  /// 未対応のため、画像を選択していて X が混ざっていると警告を出す。
  bool get _hasXSelected =>
      _selectedAccounts.any((a) => a.service == SnsService.x);

  bool get _hasBlueskySelected =>
      _selectedAccounts.any((a) => a.service == SnsService.bluesky);

  /// 画像が縮小される判定で使う、選択アカウント中で最も厳しいバイト上限。
  /// Bluesky 単独 → Bluesky の上限、X のみ → X の上限、混在 → Bluesky の上限。
  int get _strictestImageMaxBytes {
    if (_hasBlueskySelected) return ImageResizeService.blueskyMaxBytes;
    if (_hasXSelected) return ImageResizeService.xMaxBytes;
    return ImageResizeService.blueskyMaxBytes;
  }

  Future<void> _pickImages() async {
    final remaining = _maxImages - _images.length;
    if (remaining <= 0) return;
    try {
      // iOS だけ写真ピッカーの段階で縮小する。iPad/iPhone は app メモリ上限が
      // 厳しく、特に iPad の WKWebView は別プロセスで base64 を受け取ると
      // メモリ kill される。X 投稿経路（base64 → DataTransfer）の負荷も
      // 下げるため、長辺 1600 / quality 80 まで落とす。
      // Android はメモリに余裕があり、後段のリサイズ処理でも安全に処理できる
      // ためフルサイズのまま受け取る（既存挙動）。
      final picked = await _picker.pickMultiImage(
        imageQuality: Platform.isIOS ? 80 : 100,
        maxWidth: Platform.isIOS ? 1600 : null,
        maxHeight: Platform.isIOS ? 1600 : null,
        limit: remaining,
      );
      if (picked.isEmpty) return;
      final added = <_PickedImage>[];
      final base = DateTime.now().microsecondsSinceEpoch;
      var counter = 0;
      for (final xfile in picked.take(remaining)) {
        final size = await File(xfile.path).length();
        final isGif = (xfile.mimeType == 'image/gif') ||
            xfile.path.toLowerCase().endsWith('.gif');
        added.add(_PickedImage(
          id: 'img_${base}_${counter++}',
          file: xfile,
          sizeBytes: size,
          isGif: isGif,
        ));
      }
      if (!mounted) return;
      setState(() => _images.addAll(added));
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(context, '画像選択エラー: $e', type: SnackType.error);
    }
  }

  void _removeImage(int index) {
    setState(() => _images.removeAt(index));
  }

  /// サムネタップで編集メニュー（トリミング / フィルタ）を開く。
  /// GIF はどちらもアニメーション/色を壊すため対象外。
  Future<void> _editImage(int index) async {
    final picked = _images[index];
    if (picked.isGif) {
      showAppSnackBar(
        context,
        'GIF は編集できません（アニメーションを保つため）',
        type: SnackType.warning,
      );
      return;
    }
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.crop),
              title: const Text('トリミング'),
              onTap: () => Navigator.of(ctx).pop('crop'),
            ),
            ListTile(
              leading: const Icon(Icons.color_lens_outlined),
              title: const Text('フィルタ'),
              onTap: () => Navigator.of(ctx).pop('filter'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'crop':
        await _cropImage(index);
        break;
      case 'filter':
        await _filterImage(index);
        break;
    }
  }

  Future<void> _cropImage(int index) async {
    final picked = _images[index];
    try {
      final theme = Theme.of(context);
      final cropped = await ImageCropper().cropImage(
        sourcePath: picked.file.path,
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 95,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'トリミング',
            toolbarColor: theme.colorScheme.primary,
            toolbarWidgetColor: Colors.white,
            initAspectRatio: CropAspectRatioPreset.original,
            lockAspectRatio: false,
            hideBottomControls: false,
          ),
          IOSUiSettings(
            title: 'トリミング',
            aspectRatioLockEnabled: false,
            resetAspectRatioEnabled: true,
          ),
        ],
      );
      if (cropped == null) return;
      final size = await File(cropped.path).length();
      if (!mounted) return;
      setState(() {
        _images[index] = _PickedImage(
          id: 'img_${DateTime.now().microsecondsSinceEpoch}',
          file: XFile(cropped.path),
          sizeBytes: size,
          isGif: false,
        );
      });
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(context, 'トリミングエラー: $e', type: SnackType.error);
    }
  }

  Future<void> _filterImage(int index) async {
    final picked = _images[index];
    final result = await Navigator.of(context).push<XFile?>(
      MaterialPageRoute(
        builder: (_) => ImageFilterScreen(file: picked.file),
      ),
    );
    if (result == null || !mounted) return;
    final size = await File(result.path).length();
    if (!mounted) return;
    setState(() {
      _images[index] = _PickedImage(
        id: 'img_${DateTime.now().microsecondsSinceEpoch}',
        file: result,
        sizeBytes: size,
        isGif: false,
      );
    });
  }

  /// 戻る時の確認ダイアログ：「下書きに保存」「破棄」、枠外タップでキャンセル。
  /// 戻ってよければ true を返す。
  Future<bool> _confirmDiscard() async {
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: const Text('編集を破棄しますか？'),
        content: const Text('入力中の文章があります。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('save'),
            child: const Text('下書きに保存'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('discard'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('破棄'),
          ),
        ],
      ),
    );

    if (result == 'save') {
      final id = _currentDraftId ?? Draft.newId();
      final draft = Draft(
        id: id,
        updatedAt: DateTime.now(),
        text: _textController.text,
        inReplyToPost: widget.inReplyToPost,
        quotedPost: widget.quotedPost,
        failedAccountIds: const [],
      );
      await ref.read(draftListProvider.notifier).upsert(draft);
      return true;
    }
    if (result == 'discard') return true;
    // null（barrierDismissible でキャンセル）→ 戻らない
    return false;
  }

  Future<void> _openDraftList() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraftListSheet(
        onPick: (draft) {
          Navigator.of(ctx).pop();
          // 復元先を新しい画面に置き換える（reply/quote ごと差し替えるため）。
          // 一覧経由は失敗アカウントを事前選択しない仕様。
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => ComposeScreen(
                inReplyToPost: draft.inReplyToPost,
                quotedPost: draft.quotedPost,
                draft: draft,
                restoreFailedAccounts: false,
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final draftCount = ref.watch(draftListProvider).maybeWhen(
          data: (list) => list.length,
          orElse: () => 0,
        );
    return PopScope(
      canPop: !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final ok = await _confirmDiscard();
        if (ok && mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(widget.inReplyToPost != null
            ? 'リプライ'
            : widget.quotedPost != null
                ? '引用リポスト'
                : '投稿'),
        actions: [
          // ブラウザ投稿デバッグ（設定でON、X アカウント単独選択時のみ）
          if (ref.watch(settingsProvider).debugPostEnabled &&
              _selectedAccounts.length == 1 &&
              _selectedAccounts.first.service == SnsService.x)
            IconButton(
              icon: const Icon(Icons.bug_report_outlined, size: 20),
              tooltip: 'ブラウザで投稿（デバッグ）',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => BrowserPostDebugScreen(
                      account: _selectedAccounts.first,
                    ),
                  ),
                );
              },
            ),
          if (draftCount > 0)
            TextButton(
              onPressed: _openDraftList,
              child: Text('下書き ($draftCount)'),
            ),
          FilledButton(
            onPressed: _selectedAccountIds.isEmpty ||
                    (_textController.text.trim().isEmpty && _images.isEmpty)
                ? null
                : _post,
            child: const Text('投稿'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // アカウント選択（チップ横並び、複数選択。タップで toggle）
          if (_accounts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: SizedBox(
                height: 72,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  itemCount: _accounts.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final account = _accounts[i];
                    final selected = _selectedAccountIds.contains(account.id);
                    final failedBefore =
                        widget.draft?.failedAccountIds.contains(account.id) ??
                            false;
                    return _AccountChip(
                      account: account,
                      selected: selected,
                      failedBefore: failedBefore,
                      onTap: () => _toggleAccount(account),
                    );
                  },
                ),
              ),
            ),

          // リプライ先プレビュー
          if (widget.inReplyToPost != null)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border(
                  left: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                    width: 3,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      SnsBadge(service: widget.inReplyToPost!.source),
                      const SizedBox(width: 6),
                      Text(
                        widget.inReplyToPost!.username,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        widget.inReplyToPost!.handle,
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    ],
                  ),
                  if (widget.inReplyToPost!.body.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      widget.inReplyToPost!.body,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey[700], fontSize: 13),
                    ),
                  ],
                ],
              ),
            ),

          // テキスト入力
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _textController,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(
                  hintText: 'いまどうしてる？',
                  border: InputBorder.none,
                ),
                autofocus: true,
                onChanged: (_) => setState(() {}),
              ),
            ),
          ),

          // 引用元プレビュー
          if (widget.quotedPost != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 10,
                          backgroundImage: widget.quotedPost!.avatarUrl != null
                              ? CachedNetworkImageProvider(
                                  widget.quotedPost!.avatarUrl!,
                                  headers: kImageHeaders,
                                )
                              : null,
                          child: widget.quotedPost!.avatarUrl == null
                              ? Text(
                                  widget.quotedPost!.username.isNotEmpty
                                      ? widget.quotedPost!.username[0]
                                      : '?',
                                  style: const TextStyle(fontSize: 10),
                                )
                              : null,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            widget.quotedPost!.username,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            widget.quotedPost!.handle,
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (widget.quotedPost!.body.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        widget.quotedPost!.body,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ],
                ),
              ),
            ),

          // 添付画像のサムネ列（長押しで並び替え可能）
          if (_images.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: SizedBox(
                height: 80,
                child: ReorderableListView.builder(
                  scrollDirection: Axis.horizontal,
                  buildDefaultDragHandles: false,
                  itemCount: _images.length,
                  onReorder: (oldIndex, newIndex) {
                    setState(() {
                      if (newIndex > oldIndex) newIndex -= 1;
                      final item = _images.removeAt(oldIndex);
                      _images.insert(newIndex, item);
                    });
                  },
                  proxyDecorator: (child, index, animation) {
                    final primary = Theme.of(context).colorScheme.primary;
                    return AnimatedBuilder(
                      animation: animation,
                      builder: (context, c) {
                        final t = Curves.easeOut.transform(animation.value);
                        return Transform.scale(
                          scale: 1.0 + 0.08 * t,
                          child: c,
                        );
                      },
                      child: Material(
                        color: Colors.transparent,
                        elevation: 8,
                        shadowColor: primary,
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: primary, width: 2),
                          ),
                          child: child,
                        ),
                      ),
                    );
                  },
                  itemBuilder: (context, i) {
                    final picked = _images[i];
                    final hasX = _hasXSelected;
                    final hasBluesky = _hasBlueskySelected;
                    final willResize = !picked.isGif &&
                        picked.sizeBytes > _strictestImageMaxBytes;
                    final overflow = picked.isGif &&
                        ((hasX &&
                                picked.sizeBytes >
                                    ImageResizeService.xMaxBytes) ||
                            (hasBluesky &&
                                picked.sizeBytes >
                                    ImageResizeService.blueskyMaxBytes));
                    return Padding(
                      key: ValueKey(picked.id),
                      padding: const EdgeInsets.only(right: 8),
                      child: ReorderableDelayedDragStartListener(
                        index: i,
                        child: _ImageThumb(
                          picked: picked,
                          willResize: willResize,
                          overflowWarning: overflow,
                          onRemove: () => _removeImage(i),
                          onTap: () => _editImage(i),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

          // 警告ボックス（選択中の SNS で投稿失敗となる条件をリストアップ）
          if (_violations.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.warning_amber_outlined,
                            size: 16, color: Colors.orange.shade800),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '一部のアカウントは投稿失敗になります',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange.shade900,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    for (final v in _violations)
                      Padding(
                        padding: const EdgeInsets.only(left: 22, top: 2),
                        child: Text(
                          '・$v',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.orange.shade900,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

          // 機能ボタン列（画像のみ実機能、それ以外はプレースホルダー）
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(
                    Icons.image_outlined,
                    color: _images.length >= _maxImages
                        ? Colors.grey[400]
                        : Theme.of(context).colorScheme.primary,
                    size: 20,
                  ),
                  iconSize: 20,
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(),
                  tooltip: '画像を追加',
                  onPressed: _images.length >= _maxImages ? null : _pickImages,
                ),
                for (final entry in <MapEntry<IconData, String>>[
                  const MapEntry(Icons.videocam_outlined, '動画'),
                  const MapEntry(Icons.schedule_outlined, '予約投稿'),
                  const MapEntry(Icons.poll_outlined, 'アンケート'),
                  const MapEntry(Icons.reply_outlined, 'リプライ'),
                ])
                  IconButton(
                    icon: Icon(entry.key, color: Colors.grey[400], size: 20),
                    iconSize: 20,
                    padding: const EdgeInsets.all(6),
                    constraints: const BoxConstraints(),
                    tooltip: entry.value,
                    onPressed: () {
                      showAppSnackBar(
                        context,
                        '${entry.value}は対応予定なし（公式アプリをご利用ください）',
                        type: SnackType.warning,
                        duration: const Duration(seconds: 2),
                      );
                    },
                  ),
              ],
            ),
          ),

          // 文字数カウンター
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  '$_remaining',
                  style: TextStyle(
                    color: _remaining < 0
                        ? Colors.red
                        : _remaining < 20
                            ? Colors.orange
                            : Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }
}

class _AccountChip extends StatelessWidget {
  const _AccountChip({
    required this.account,
    required this.selected,
    required this.onTap,
    this.failedBefore = false,
  });

  final Account account;
  final bool selected;
  final VoidCallback onTap;

  /// 失敗下書きから再投稿で開いた場合、このアカウントが失敗側に含まれているか。
  /// true なら左上に小さい赤い ! マークを overlay する。
  final bool failedBefore;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final borderColor = failedBefore
        ? Colors.red.shade700
        : selected
            ? primary
            : Theme.of(context).dividerColor;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 64,
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? primary.withValues(alpha: 0.12) : null,
          border: Border.all(
            color: borderColor,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Opacity(
              opacity: selected ? 1.0 : 0.55,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundImage: account.avatarUrl != null
                        ? CachedNetworkImageProvider(
                            account.avatarUrl!,
                            headers: kImageHeaders,
                          )
                        : null,
                    child: account.avatarUrl == null
                        ? Text(
                            account.displayName.isNotEmpty
                                ? account.displayName[0]
                                : '?',
                            style: const TextStyle(fontSize: 12),
                          )
                        : null,
                  ),
                  Positioned(
                    right: -4,
                    bottom: -2,
                    child: SnsBadge(service: account.service, size: 7),
                  ),
                  if (failedBefore)
                    Positioned(
                      left: -4,
                      top: -4,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.error,
                          size: 14,
                          color: Colors.red.shade700,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              account.handle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                color: selected ? null : Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickedImage {
  const _PickedImage({
    required this.id,
    required this.file,
    required this.sizeBytes,
    this.isGif = false,
  });
  final String id;
  final XFile file;
  final int sizeBytes;
  final bool isGif;
}

class _ImageThumb extends StatelessWidget {
  const _ImageThumb({
    required this.picked,
    required this.willResize,
    required this.onRemove,
    this.overflowWarning = false,
    this.onTap,
  });

  final _PickedImage picked;
  final bool willResize;
  final bool overflowWarning;
  final VoidCallback onRemove;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 80,
      height: 80,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          GestureDetector(
            onTap: onTap,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                File(picked.file.path),
                width: 80,
                height: 80,
                fit: BoxFit.cover,
              ),
            ),
          ),
          // 縮小予定マーク（左下、通常画像で再エンコード対象のとき）
          if (willResize)
            Positioned(
              left: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.compress, size: 10, color: Colors.white),
                    SizedBox(width: 2),
                    Text(
                      '縮小',
                      style: TextStyle(
                        fontSize: 9,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // 容量超過マーク（GIF が選択中 SNS の上限を超えるとき）
          if (overflowWarning)
            Positioned(
              left: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.red.shade700.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, size: 10, color: Colors.white),
                    SizedBox(width: 2),
                    Text(
                      '容量超',
                      style: TextStyle(
                        fontSize: 9,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // 削除ボタン（右上）
          Positioned(
            top: -6,
            right: -6,
            child: InkWell(
              onTap: onRemove,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: Colors.white, width: 1),
                ),
                child: const Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


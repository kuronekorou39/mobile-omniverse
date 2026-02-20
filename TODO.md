# OmniVerse TODO

## バグ修正

- [x] **Google ログインで白画面**: `shouldOverrideUrlLoading` + `thirdPartyCookiesEnabled` で OAuth リダイレクト許可済み
- [ ] **Bluesky スレッド取得の DID 不一致**: 他ユーザーの投稿詳細を開くとき、投稿者の DID ではなく自分の DID で URI を構築してしまう問題

## タイムライン投稿の表示改善

### エンゲージメント表示・操作
- [x] **リプライ数・ふぁぼ数・RT数の表示**: PostCard にエンゲージメント行を追加
- [x] **ふぁぼボタン**: X (FavoriteTweet/UnfavoriteTweet) / Bluesky (createRecord/deleteRecord) API 連携 + 楽観的更新
- [x] **リツイート/リポストボタン**: X (CreateRetweet/DeleteRetweet) / Bluesky (repost) API 連携 + 楽観的更新

### 投稿詳細・リプライ
- [x] **投稿タップで詳細表示**: PostDetailScreen でリプライ一覧を表示 (X: TweetDetail / Bluesky: getPostThread)
- [ ] **タイムライン上のアコーディオン展開**: タイムライン上でも投稿を展開してリプライをインライン表示

### メディア・リンク
- [x] **画像表示**: 1〜4枚グリッド表示 + タップでフルスクリーン ImageViewer (ピンチズーム対応)
- [ ] **動画インライン再生**: 現状サムネイル + 再生アイコン → 外部ブラウザ。インラインプレーヤー (video_player) 未実装
- [x] **URL のリンク化**: 本文中 URL を正規表現で検出し、タップで url_launcher 起動
- [x] **テキスト選択・コピー**: 詳細画面で SelectableText 対応

### 投稿元アカウント識別
- [x] **取得元アカウント表示**: PostCard のハンドル横に "via @account" を小さく表示

## UI/UX 改善

### レイアウト
- [x] **スクロール時ヘッダー非表示**: SliverAppBar (floating: true, snap: true) で実装
- [x] **アカウントタブをヘッダーに移動**: BottomNavigationBar 廃止、AppBar に人型アイコンボタン配置
- [x] **投稿ボタン (FAB)**: Scaffold.floatingActionButton に配置 (投稿画面は placeholder)

### パフォーマンス・アニメーション
- [x] **アニメーション追加**: PageRouteBuilder でスライドイン遷移、Hero アニメーション (アバター)
- [ ] **リスト表示アニメーション**: 新規投稿の SlideTransition / AnimatedList 未実装
- [ ] **ボタンタップアニメーション**: いいね/RT の ScaleTransition フィードバック未実装
- [ ] **スムーズなスクロール**: タイムラインのスクロールパフォーマンス最適化

## 基本動作の拡充

- [x] **Pull-to-refresh**: 実装済み（RefreshIndicator）
- [x] **重複排除**: 実装済み（post.id による Map マージ）
- [x] **無限スクロール**: ScrollController + 下端検出 → loadMore()。カーソルパラメータ対応済み
- [x] **エラー状態の表示**: MaterialBanner でエラーバナー + リトライ/閉じるボタン

## 投稿・ソーシャル機能

- [ ] **ブックマーク/保存**: 投稿をアプリ内に保存して後で見返す (SharedPreferences / DB)
- [x] **シェア**: 投稿詳細画面から share_plus で permalink を OS シェアシートに連携
- [ ] **引用リツイート/引用リポスト**: 引用付きで RT/リポスト
- [x] **ユーザープロフィール表示**: UserProfileScreen の骨格実装済み (詳細情報の API 取得は未実装)
- [ ] **フォロー/アンフォロー**: アプリ内からフォロー操作
- [ ] **投稿作成**: テキスト投稿の作成・送信機能

## セキュリティ・信頼性

- [x] **認証情報の安全な保存**: flutter_secure_storage に移行済み (SharedPreferences からの自動マイグレーション付き)
- [ ] **トークン自動リフレッシュ UI**: Bluesky の accessJwt 期限切れ時、ユーザーに再ログインを促す通知
- [ ] **生体認証ロック**: アプリ起動時に指紋/顔認証（オプション）
- [ ] **レート制限ハンドリング**: API レート制限到達時の適切な待機と通知

## 見た目・ブランディング

- [x] **ダークモード/テーマ切替**: ライト・ダーク・システム準拠の3択 (設定永続化済み)
- [x] **フォントサイズ調整**: 設定からスライダーで 80%〜150% 変更可能 (MediaQuery.textScaler)
- [ ] **スプラッシュスクリーン**: flutter_native_splash で起動時ブランド表示
- [ ] **アプリアイコン**: flutter_launcher_icons で OmniVerse 専用アイコン作成
- [ ] **通知**: 新着投稿やメンションのプッシュ通知

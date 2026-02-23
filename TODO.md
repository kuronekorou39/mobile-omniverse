# OmniVerse TODO

## バグ修正

- [x] **Google ログインで白画面**: `shouldOverrideUrlLoading` + `thirdPartyCookiesEnabled` で OAuth リダイレクト許可済み
- [x] **詳細画面の画像が入れ子で2重表示**: PostCard を直接埋め込んでいたのを共有ウィジェット (PostImageGrid) に分離
- [x] **詳細画面のリンクがテキストのまま**: SelectableText → LinkedText (共有ウィジェット) に置き換え
- [x] **ふぁぼ/RT が実際に反映されない**: queryId 動的取得 + デバッグログ追加で対応済み
- [ ] **Bluesky スレッド取得の DID 不一致**: 他ユーザーの投稿詳細を開くとき、投稿者の DID ではなく自分の DID で URI を構築してしまう問題

## queryId 自動更新 (v1.1.0〜)

- [x] **XQueryIdService**: x.com の JS バンドルから queryId を自動取得・SharedPreferences にキャッシュ
- [x] **GET 系 404 リトライ**: タイムライン・ツイート詳細の 404 で queryId リフレッシュ → リトライ
- [x] **mutation は 404 リトライしない**: いいね/RT 等の 404 はアカウント制限等が原因のため、queryId リフレッシュを発動しない
- [x] **データ保護**: リフレッシュ後にユーザー情報が欠けた投稿で既存の正常データを上書きしない
- [x] **queryId 差分表示**: 設定画面でリフレッシュ前後の値をダイアログ表示
- [x] **キャッシュ消去**: 設定画面からキャッシュを消去してデフォルト値に戻す機能
- [x] **ログイン時フォールバック**: UserByRestId 失敗時に fetch interceptor データにフォールバック

## アプリ更新チェック (v1.1.0〜)

- [x] **GitHub Releases チェック**: 起動時 + 設定画面から手動で最新リリースを確認
- [x] **バージョン比較**: semver 比較で新しいバージョンを検出
- [x] **更新ダイアログ**: バージョン番号 + リリースノート表示、ブラウザで APK ダウンロード
- [x] **動的バージョン表示**: package_info_plus で設定画面にバージョン表示

## 画像表示

- [x] **CachedNetworkImage にブラウザ User-Agent ヘッダー追加**: pbs.twimg.com の画像読み込み改善
- [x] **アバター画像エラー時フォールバック**: CachedNetworkImage の errorWidget でイニシャル表示

## タイムライン投稿の表示改善

### エンゲージメント表示・操作
- [x] **リプライ数・ふぁぼ数・RT数の表示**: PostCard にエンゲージメント行を追加
- [x] **ふぁぼボタン**: X (FavoriteTweet/UnfavoriteTweet) / Bluesky (createRecord/deleteRecord) API 連携 + 楽観的更新
- [x] **リツイート/リポストボタン**: X (CreateRetweet/DeleteRetweet) / Bluesky (repost) API 連携 + 楽観的更新
- [ ] **アカウント選択モーダル**: いいね/RT 時にどのアカウントで実行するかモーダルで選択。設定でモーダル表示の ON/OFF を切り替え（OFF の場合は投稿取得元アカウントで自動実行）

### 投稿詳細・リプライ
- [x] **投稿タップで詳細表示**: PostDetailScreen でリプライ一覧を表示 (X: TweetDetail / Bluesky: getPostThread)
- [ ] **タイムライン上のアコーディオン展開**: タイムライン上でも投稿を展開してリプライをインライン表示

### メディア・リンク
- [x] **画像表示**: 1〜4枚グリッド表示 + タップでフルスクリーン ImageViewer (ピンチズーム対応)
- [ ] **動画インライン再生**: 現状サムネイル + 再生アイコン → 外部ブラウザ。インラインプレーヤー (video_player) 未実装
- [x] **URL のリンク化**: 本文中 URL を正規表現で検出し、タップで url_launcher 起動
- [x] **テキスト選択・コピー**: 詳細画面で LinkedText (selectable) 対応

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
- [ ] **アカウント追加時の待機演出**: ヘッダーにアニメーション + ランダムな愚痴メッセージ表示 (「おそいね」「もうちょっとまってね」「処理中、、」等)

### アカウント管理
- [ ] **アカウントのセッション生存確認**: アカウント一覧で各アカウントのセッションが有効か表示。サーバーダウンも検出
- [ ] **アカウントごとの RT 非表示フィルタ**: アカウント設定でリツイート/リポストを非表示にするオプション

## 基本動作の拡充

- [x] **Pull-to-refresh**: 実装済み（RefreshIndicator）
- [x] **重複排除**: 実装済み（post.id による Map マージ）
- [x] **無限スクロール**: ScrollController + 下端検出 → loadMore()。カーソルパラメータ対応済み
- [x] **エラー状態の表示**: MaterialBanner でエラーバナー + リトライ/閉じるボタン

## 投稿・ソーシャル機能

- [ ] **ブックマーク/保存**: 投稿をアプリ内に保存して後で見返す (SharedPreferences / DB)
- [x] **シェア**: 投稿詳細画面から share_plus で permalink を OS シェアシートに連携
- [ ] **引用リツイート/引用リポスト**: 引用付きで RT/リポスト
- [ ] **ユーザープロフィール + 個人TL**: アバタータップ等でユーザー詳細画面に遷移。プロフィール情報表示 + 個人タイムライン取得・表示。プロフィール画面の骨格は実装済み、個人TL取得が未実装
- [ ] **フォロー/アンフォロー**: ユーザー詳細画面からフォロー/アンフォロー操作 (X: CreateFriendship/DestroyFriendship, Bluesky: app.bsky.graph.follow)
- [ ] **投稿作成**: テキスト投稿の作成・送信機能
- [x] **RT の表示形式改善**: 通常 RT と引用 RT を区別して表示

## データ永続化

- [ ] **タイムラインの永続化**: アプリ再起動時に前回のタイムラインを保持。ローカル DB (sqflite / drift) または JSON ファイルにキャッシュし、起動時に即表示 → バックグラウンドで最新を取得
- [ ] **既読位置の保存**: 最後に読んだ投稿の位置を記憶し、再起動後にその位置から表示

## 通知・統合

- [ ] **アカウントごとの統合通知欄**: 全アカウントの通知 (メンション・いいね・RT・フォロー等) を統合して一覧表示。X: Notifications API / Bluesky: listNotifications
- [ ] **通知バッジ**: 未読通知数をアプリアイコンやヘッダーにバッジ表示

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

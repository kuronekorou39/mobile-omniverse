# OmniVerse

複数SNS（X / Bluesky）のタイムラインを統合表示するAndroidアプリ。

## 機能

- **統合タイムライン**: 複数アカウント・複数SNSの投稿を1つのフィードに時系列表示
- **マルチアカウント**: X 最大4アカウント + Bluesky 複数アカウントに対応
- **投稿**: 通常投稿 / リプライ / 引用RT（X はDOM操作方式でbot検知を回避）
- **エンゲージメント**: いいね / リポスト / ブックマーク
- **通知**: 全アカウント統合通知 + アカウント別通知
- **ユーザーホーム**: 投稿一覧 / メディア一覧 / フォロー・フォロワー数
- **カスタマイズ**: テーマ（ダーク/ライト）、フォント（Google Fonts）、フォントサイズ

## 技術スタック

- **Flutter** (Dart)
- **Riverpod** (状態管理)
- **flutter_inappwebview** (WebView / OAuth)
- **flutter_secure_storage** (認証情報の暗号化保存)

## ビルド

```bash
export PATH="/path/to/flutter/bin:/path/to/jdk/bin:$PATH"
export JAVA_HOME="/path/to/jdk"
flutter build apk --release
```

## リリース

```bash
# pubspec.yaml の version をインクリメント後:
VERSION=$(grep '^version:' pubspec.yaml | sed 's/version: //' | cut -d+ -f1)
git tag "v${VERSION}"
git push origin "v${VERSION}"
```

タグをpushすると GitHub Actions が自動でAPKをビルドしリリースを作成します。

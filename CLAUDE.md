# OmniVerse 開発ルール

## リリース手順（必ず守ること）

コード変更をリリースする際は、以下を**毎回**実行すること:

1. `pubspec.yaml` の `version` をインクリメント（例: `1.1.2+4` → `1.1.3+5`）
2. 変更をコミット＆push
3. タグを作成＆push → GitHub Actions が自動でビルド＆リリース作成

**同じバージョン番号でリリースを差し替えない。** アプリ内の更新チェックはバージョン番号の比較で動作するため、番号が変わらないと検知できない。

## リリースコマンド

```bash
VERSION=$(grep '^version:' pubspec.yaml | sed 's/version: //' | cut -d+ -f1)
git tag "v${VERSION}"
git push origin "v${VERSION}"
```

タグをpushすると、GitHub Actions (`.github/workflows/release.yml`) が自動で:
- リリースAPKをビルド
- `OmniVerse-v{VERSION}.apk` にリネーム
- GitHub Releaseを作成してAPKを添付

## ローカルビルド（デバッグ用）

```bash
export PATH="/c/development/flutter/bin:/c/Java/jdk-17.0.2/bin:/c/Android/platform-tools:$PATH"
export JAVA_HOME="C:\\Java\\jdk-17.0.2"
flutter build apk --release
```

## queryId 自動更新の注意点

- mutation（いいね/RT等）の 404 で queryId リフレッシュを発動しない（アカウント制限等の誤検知防止）
- GET 系（タイムライン/ツイート詳細）の 404 のみリトライ対象
- リフレッシュ後にユーザー情報が欠けた投稿で既存データを上書きしない

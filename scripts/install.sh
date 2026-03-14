#!/bin/bash
# OmniVerse ビルド＆インストール＆権限付与スクリプト
# 使い方: bash scripts/install.sh [device_serial]

set -e

export PATH="/c/development/flutter/bin:/c/Java/jdk-17.0.2/bin:/c/Android/platform-tools:$PATH"
export JAVA_HOME="C:\\Java\\jdk-17.0.2"

APK="build/app/outputs/flutter-apk/app-debug.apk"
PKG="com.omniverse.mobile_omniverse"

# デバイス指定
SERIAL="${1:-}"
ADB_CMD="adb"
if [ -n "$SERIAL" ]; then
  ADB_CMD="adb -s $SERIAL"
fi

# 接続確認
echo "=== デバイス確認 ==="
$ADB_CMD get-state > /dev/null 2>&1 || { echo "エラー: デバイスが見つかりません"; exit 1; }
echo "デバイス: $($ADB_CMD shell getprop ro.product.model) (Android $($ADB_CMD shell getprop ro.build.version.release))"

# ビルド
echo ""
echo "=== ビルド ==="
flutter build apk --debug

# インストール（既存があれば上書き、失敗したらアンインストールしてリトライ）
echo ""
echo "=== インストール ==="
if ! $ADB_CMD install -r "$APK" 2>&1; then
  echo "上書きインストール失敗 → アンインストールしてリトライ"
  $ADB_CMD uninstall "$PKG" 2>/dev/null || true
  $ADB_CMD install "$APK"
fi

# オーバーレイ権限を付与
echo ""
echo "=== オーバーレイ権限付与 ==="
$ADB_CMD shell appops set "$PKG" SYSTEM_ALERT_WINDOW allow
echo "SYSTEM_ALERT_WINDOW: $($ADB_CMD shell appops get "$PKG" SYSTEM_ALERT_WINDOW)"

echo ""
echo "=== 完了 ==="

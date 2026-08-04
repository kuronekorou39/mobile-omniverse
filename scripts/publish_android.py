"""Android の配信を1コマンドで済ませる。

GitHub Release にできた APK を rou39.com (S3) に置き、アプリ内の更新チェックが
見ている update.json を書き換えて、ポートフォリオ側にコミットするまでを通す。

iOS は App Store の照会 API を見ているのでこのスクリプトの対象外。
Android だけが自前配布なので、ここを忘れると更新が誰にも届かない。

使い方:
    # タグを push して GitHub Actions のビルドが終わったあとに実行する
    python scripts/publish_android.py --notes "フォロー取得の不具合を修正"

    python scripts/publish_android.py --notes "..." --dry-run   # 何もせず確認だけ
    python scripts/publish_android.py --notes "..." --no-push   # commit まで

前提: gh / aws CLI が認証済みであること。
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")

REPO_ROOT = Path(__file__).resolve().parent.parent

# 運用で変わる値。環境変数で上書きできる。
PORTFOLIO_DIR = Path(os.environ.get("PORTFOLIO_DIR", r"C:\projects\portfolio-rou39-dev"))
S3_BUCKET = os.environ.get("OMNIVERSE_S3_BUCKET", "rou39-site")
S3_PREFIX = "omniverse"
CLOUDFRONT_ID = os.environ.get("OMNIVERSE_CLOUDFRONT_ID", "E2MX55DRRVJ7XR")
SITE_BASE = "https://rou39.com/omniverse"

UPDATE_JSON_REL = Path("frontend/public/omniverse/update.json")
APK_CONTENT_TYPE = "application/vnd.android.package-archive"

dry_run = False


def run(cmd, **kw):
    """コマンドを実行する。--dry-run なら中身を見せるだけ。"""
    shown = " ".join(str(c) for c in cmd)
    if dry_run:
        print(f"  [dry-run] {shown}")
        return ""
    print(f"  $ {shown}")
    r = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8",
                       errors="replace", **kw)
    if r.returncode != 0:
        sys.exit(f"❌ 失敗 (exit {r.returncode}): {shown}\n{(r.stderr or r.stdout)[:600]}")
    return r.stdout or ""


def read_version() -> str:
    text = (REPO_ROOT / "pubspec.yaml").read_text(encoding="utf-8")
    m = re.search(r"^version:\s*([0-9]+(?:\.[0-9]+)*)", text, re.M)
    if not m:
        sys.exit("❌ pubspec.yaml から version を読めなかった")
    return m.group(1)


def main():
    global dry_run

    p = argparse.ArgumentParser(description="Android の配信を更新する")
    p.add_argument("--notes", required=True, help="更新ダイアログに出すリリースノート")
    p.add_argument("--version", help="省略時は pubspec.yaml の値")
    p.add_argument("--no-push", action="store_true", help="commit までで止める")
    p.add_argument("--dry-run", action="store_true", help="実行せず内容だけ出す")
    args = p.parse_args()

    dry_run = args.dry_run
    version = args.version or read_version()
    apk_name = f"OmniVerse-v{version}.apk"
    tag = f"v{version}"

    print(f"OmniVerse {version} を Android 向けに配信")
    if dry_run:
        print("(dry-run: 何も変更しない)")

    update_json = PORTFOLIO_DIR / UPDATE_JSON_REL
    if not update_json.exists():
        sys.exit(f"❌ update.json が見つからない: {update_json}\n"
                 f"   PORTFOLIO_DIR 環境変数で場所を指定できる")

    current = json.loads(update_json.read_text(encoding="utf-8"))
    if current.get("version") == version and not dry_run:
        print(f"⚠ update.json は既に {version} です。APK の再配置だけ行います")

    tmp = Path(tempfile.mkdtemp(prefix="omniverse-publish-"))
    try:
        print(f"\n[1/5] GitHub Release {tag} から APK を取得")
        run(["gh", "release", "download", tag, "-p", apk_name,
             "--dir", str(tmp), "--clobber"])
        apk = tmp / apk_name
        if not dry_run:
            size = apk.stat().st_size
            # SPA のフォールバック HTML を掴んでいないか、大きさで気づけるようにする
            if size < 10 * 1024 * 1024:
                sys.exit(f"❌ APK が小さすぎる ({size} bytes)。取得に失敗している可能性")
            print(f"      {size:,} bytes")

        print("\n[2/5] S3 に配置")
        run(["aws", "s3", "cp", str(apk), f"s3://{S3_BUCKET}/{S3_PREFIX}/{apk_name}",
             "--content-type", APK_CONTENT_TYPE])

        print("\n[3/5] update.json を更新")
        payload = {
            "version": version,
            "release_notes": args.notes,
            "apk_url": f"{SITE_BASE}/{apk_name}",
        }
        body = json.dumps(payload, ensure_ascii=False, indent=2) + "\n"
        print("      " + body.replace("\n", "\n      ").rstrip())
        if not dry_run:
            update_json.write_text(body, encoding="utf-8")
        run(["aws", "s3", "cp", str(update_json),
             f"s3://{S3_BUCKET}/{S3_PREFIX}/update.json",
             "--content-type", "application/json"])

        print("\n[4/5] CloudFront のキャッシュを無効化")
        run(["aws", "cloudfront", "create-invalidation",
             "--distribution-id", CLOUDFRONT_ID,
             "--paths", f"/{S3_PREFIX}/update.json"],
            env={**os.environ, "MSYS_NO_PATHCONV": "1"})

        print("\n[5/5] ポートフォリオ側をコミット")
        run(["git", "-C", str(PORTFOLIO_DIR), "add", str(UPDATE_JSON_REL)])
        msg = f"chore: OmniVerse の更新情報を {version} に更新"
        # 中身が変わっていなければ commit は失敗するので、その場合は飛ばす
        diff = run(["git", "-C", str(PORTFOLIO_DIR), "diff", "--cached", "--name-only"])
        if dry_run or diff.strip():
            run(["git", "-C", str(PORTFOLIO_DIR), "commit", "-m", msg])
            if not args.no_push:
                run(["git", "-C", str(PORTFOLIO_DIR), "push", "origin", "main"])
        else:
            print("      変更なし。commit をスキップ")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    print(f"\n✅ 完了: {SITE_BASE}/update.json が {version} を指しています")
    if args.no_push and not dry_run:
        print("   （push はしていません。手動で push してください）")


if __name__ == "__main__":
    main()

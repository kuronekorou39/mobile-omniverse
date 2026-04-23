#!/usr/bin/env python3
"""
flutter_inappwebview_ios の windowId WebView クラッシュ workaround パッチ。

upstream PR #2776 (未マージ) の差分を、ローカルの pub-cache にある
plugin source に当てる。iOS 14-17 で windowId 経由で作られた子 WebView の
contentWorld 未初期化バグによる EXC_BAD_ACCESS を回避する。

iOS 18+ ではこのパッチは無効化され元の動作のまま。
iOS 14-17 では windowId WebView に対してのみ legacy evaluateJavaScript API
を使うように分岐する。

参考: https://github.com/pichillilorenzo/flutter_inappwebview/pull/2776
"""
import sys
from pathlib import Path

PATCH_MARKER = "OMNIVERSE_PATCH_2776"

# 元コードに対する replacement（インデント込み完全一致を狙う）
# 行頭スペース 8 個（8-space indent）はクラスメソッド内なので Swift 標準
NEEDLE_EVAL = "        super.evaluateJavaScript(javaScript, in: frame, in: contentWorld, completionHandler: completionHandler)"
PATCH_EVAL = """        // OMNIVERSE_PATCH_2776: iOS 14-17 windowId WebView crash workaround
        // (upstream PR #2776, not yet merged)
        if #unavailable(iOS 18.0), windowId != nil {
            super.evaluateJavaScript(javaScript) { result, error in
                if let error = error {
                    completionHandler?(.failure(error))
                } else {
                    completionHandler?(.success(result as Any))
                }
            }
            return
        }
        super.evaluateJavaScript(javaScript, in: frame, in: contentWorld, completionHandler: completionHandler)"""

NEEDLE_CALL = "        super.callAsyncJavaScript(functionBody, arguments: arguments, in: frame, in: contentWorld, completionHandler: completionHandler)"
PATCH_CALL = """        // OMNIVERSE_PATCH_2776: iOS 14-17 windowId WebView crash workaround
        if #unavailable(iOS 18.0), windowId != nil {
            super.callAsyncJavaScript(functionBody, arguments: arguments, in: frame, in: WKContentWorld.page, completionHandler: completionHandler)
            return
        }
        super.callAsyncJavaScript(functionBody, arguments: arguments, in: frame, in: contentWorld, completionHandler: completionHandler)"""


def find_inappwebview_swift():
    """ありうる場所を全部探す。pub-cache、symlinks、Pods いずれにも対応。"""
    bases = [
        Path.home() / ".pub-cache" / "hosted" / "pub.dev",
        Path("ios") / ".symlinks" / "plugins" / "flutter_inappwebview_ios",
        Path("ios") / "Pods" / "flutter_inappwebview_ios",
    ]
    found = []
    for base in bases:
        if not base.exists():
            continue
        for swift_file in base.rglob("InAppWebView.swift"):
            if "flutter_inappwebview_ios" in str(swift_file):
                found.append(swift_file)
    return found


def patch_file(path: Path) -> bool:
    content = path.read_text()
    if PATCH_MARKER in content:
        print(f"  [skip] {path} (already patched)")
        return False

    patched = content
    eval_done = False
    call_done = False

    if NEEDLE_EVAL in patched:
        patched = patched.replace(NEEDLE_EVAL, PATCH_EVAL, 1)
        eval_done = True
    if NEEDLE_CALL in patched:
        patched = patched.replace(NEEDLE_CALL, PATCH_CALL, 1)
        call_done = True

    if not eval_done and not call_done:
        print(f"  [warn] {path} - no needle found, plugin internals may have changed")
        return False
    if not eval_done:
        print(f"  [warn] {path} - eval needle not found")
    if not call_done:
        print(f"  [warn] {path} - call needle not found")

    path.write_text(patched)
    print(f"  [patched] {path} (eval={eval_done}, call={call_done})")
    return True


def main():
    print("[patch_inappwebview] Searching for InAppWebView.swift...")
    files = find_inappwebview_swift()
    if not files:
        print("ERROR: InAppWebView.swift not found", file=sys.stderr)
        sys.exit(1)

    print(f"[patch_inappwebview] Found {len(files)} file(s):")
    for f in files:
        print(f"  - {f}")

    print("[patch_inappwebview] Applying patch...")
    patched_any = False
    for f in files:
        if patch_file(f):
            patched_any = True

    if not patched_any:
        print("[patch_inappwebview] No files were patched (already patched?)")
        # already-patched is OK for re-runs, don't fail
    print("[patch_inappwebview] Done.")


if __name__ == "__main__":
    main()

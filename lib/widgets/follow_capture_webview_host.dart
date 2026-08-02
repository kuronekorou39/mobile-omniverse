import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../services/follow_capture_webview_service.dart';
import '../utils/platform_ua.dart';

/// フォロー/フォロワー走査用の WebView を 1 枚ホストするウィジェット。
///
/// HeadlessInAppWebView だと捕獲はできても再送が必ず 404 になるため
/// (ビューポート・ペース・txId 寿命・ct0 ずれはいずれも実測で否定済み)、
/// **実表示の WebView** を使う必要がある。
/// 画面には出したくないので、実サイズのまま画面外に配置する。
/// サイズを潰すと X にビューポート不整合と見なされる恐れがあるため、
/// 1px にはせず実機相当のまま逃がしている。
class FollowCaptureWebViewHost extends StatelessWidget {
  const FollowCaptureWebViewHost({super.key});

  /// 画面外に逃がす距離。Stack の直接の子として使う [Positioned] は
  /// 呼び出し側が持つ（ValueListenableBuilder を挟むと Positioned が
  /// Stack の直接の子でなくなり実行時エラーになるため）
  static const offscreenX = -3000.0;
  static const size = Size(412, 915);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size.width,
      height: size.height,
      child: InAppWebView(
        initialUrlRequest: URLRequest(url: WebUri('about:blank')),
        initialUserScripts: UnmodifiableListView([
          UserScript(
            source: FollowCaptureWebViewService.interceptorScript,
            injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          ),
        ]),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          userAgent: platformUserAgent,
          domStorageEnabled: true,
          thirdPartyCookiesEnabled: true,
        ),
        onWebViewCreated: FollowCaptureWebViewService.instance.attach,
        onLoadStop: (controller, url) {
          controller.evaluateJavascript(
              source: FollowCaptureWebViewService.interceptorScript);
        },
      ),
    );
  }
}

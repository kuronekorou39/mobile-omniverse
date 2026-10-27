import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 長い取得を裏で続けるための、Android 側への窓口。
///
/// 中身は MainActivity と JobForegroundService にある。iOS や試験では
/// 何もしない（呼んでも安全）。
class AndroidBackground {
  AndroidBackground._();

  static const _channel = MethodChannel('com.omniverse/background_job');

  static bool get _available => !kIsWeb && Platform.isAndroid;

  /// 通知の「中断」が押されたときに呼ぶ
  static void setCancelHandler(VoidCallback onCancel) {
    if (!_available) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'cancelRequested') onCancel();
    });
  }

  /// 通知を出して、裏に回っても止まらないようにする。
  /// アプリが前に出ているときしか始められない。始められなければ false
  static Future<bool> start(
      {required String title, required String text, int done = 0, int total = 0}) async {
    if (!_available) return false;
    try {
      return await _channel.invokeMethod<bool>('start', {
            'title': title,
            'text': text,
            'done': done,
            'total': total,
          }) ??
          false;
    } catch (e) {
      debugPrint('[AndroidBackground] start: $e');
      return false;
    }
  }

  static Future<void> update(
      {required String title, required String text, int done = 0, int total = 0}) async {
    if (!_available) return;
    try {
      await _channel.invokeMethod('update', {
        'title': title,
        'text': text,
        'done': done,
        'total': total,
      });
    } catch (e) {
      debugPrint('[AndroidBackground] update: $e');
    }
  }

  static Future<void> stop() async {
    if (!_available) return;
    try {
      await _channel.invokeMethod('stop');
    } catch (e) {
      debugPrint('[AndroidBackground] stop: $e');
    }
  }

  /// 通知を出す許可を求める（Android 13 以降）。断られても取得は続く
  static Future<void> requestNotificationPermission() async {
    if (!_available) return;
    try {
      await _channel.invokeMethod('requestNotificationPermission');
    } catch (e) {
      debugPrint('[AndroidBackground] permission: $e');
    }
  }

  /// HeadlessInAppWebView を「見えているが画面の外」に直す
  static Future<bool> revealWebView(String id) async {
    if (!_available) return false;
    try {
      return await _channel.invokeMethod<bool>('revealWebView', {'id': id}) ??
          false;
    } catch (e) {
      debugPrint('[AndroidBackground] reveal: $e');
      return false;
    }
  }
}

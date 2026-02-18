import 'dart:convert';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/sns_service.dart';

class CookiePersistenceService {
  CookiePersistenceService._();
  static final instance = CookiePersistenceService._();

  static const _prefix = 'cookies_';

  /// アカウント別に Cookie を保存
  Future<void> saveCookiesForAccount(
      String accountId, SnsService service) async {
    final cookieManager = CookieManager.instance();
    final cookies = await cookieManager.getCookies(
      url: WebUri('https://${service.domain}'),
    );

    final cookieList = cookies
        .map((c) => {
              'name': c.name,
              'value': c.value,
              'domain': c.domain ?? service.domain,
              'path': c.path ?? '/',
            })
        .toList();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_prefix${accountId}',
      json.encode(cookieList),
    );
  }

  /// アカウント別の Cookie を復元
  Future<void> restoreCookiesForAccount(
      String accountId, SnsService service) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefix$accountId');
    if (raw == null) return;

    final cookieManager = CookieManager.instance();
    final List<dynamic> cookieList = json.decode(raw);

    for (final c in cookieList) {
      final map = c as Map<String, dynamic>;
      await cookieManager.setCookie(
        url: WebUri('https://${service.domain}'),
        name: map['name'] as String,
        value: map['value'] as String,
        domain: map['domain'] as String?,
        path: map['path'] as String? ?? '/',
      );
    }
  }

  /// アカウントの Cookie を削除
  Future<void> deleteCookiesForAccount(String accountId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$accountId');
  }

  /// ドメインの Cookie をクリア（ログイン用 WebView で使用）
  Future<void> clearCookiesForDomain(SnsService service) async {
    final cookieManager = CookieManager.instance();
    await cookieManager.deleteCookies(
      url: WebUri('https://${service.domain}'),
    );
  }
}

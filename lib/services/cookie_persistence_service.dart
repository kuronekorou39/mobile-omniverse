import 'dart:convert';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/sns_service.dart';

class CookiePersistenceService {
  CookiePersistenceService._();
  static final instance = CookiePersistenceService._();

  static const _prefix = 'cookies_';

  Future<void> saveCookies(SnsService service) async {
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
    await prefs.setString('$_prefix${service.name}', json.encode(cookieList));
  }

  Future<void> restoreCookies(SnsService service) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefix${service.name}');
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

  Future<void> restoreAll() async {
    for (final service in SnsService.values) {
      await restoreCookies(service);
    }
  }

  Future<void> saveAll() async {
    for (final service in SnsService.values) {
      await saveCookies(service);
    }
  }
}

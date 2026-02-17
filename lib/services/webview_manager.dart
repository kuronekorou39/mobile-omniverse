import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../models/post.dart';
import '../models/sns_service.dart';
import 'scraper_service.dart';
import 'x_scraper.dart';
import 'bluesky_scraper.dart';

class WebViewManager {
  WebViewManager._();
  static final instance = WebViewManager._();

  final Map<SnsService, InAppWebViewController> _controllers = {};

  final Map<SnsService, ScraperService> _scrapers = {
    SnsService.x: XScraper(),
    SnsService.bluesky: BlueskyScraper(),
  };

  Function(List<Post> posts, SnsService source)? onPostsScraped;

  void registerController(SnsService service, InAppWebViewController controller) {
    _controllers[service] = controller;
    debugPrint('[OmniVerse] Registered controller for ${service.label}');
  }

  void unregisterController(SnsService service) {
    _controllers.remove(service);
  }

  bool hasController(SnsService service) => _controllers.containsKey(service);

  Future<List<Post>> scrape(SnsService service) async {
    final controller = _controllers[service];
    if (controller == null) {
      debugPrint('[OmniVerse] No controller for ${service.label} - skip scrape');
      return [];
    }

    final scraper = _scrapers[service];
    if (scraper == null) return [];

    debugPrint('[OmniVerse] Scraping ${service.label}...');

    try {
      final result = await controller.evaluateJavascript(
        source: scraper.scrapingScript,
      );

      debugPrint('[OmniVerse] ${service.label} raw result type: ${result.runtimeType}');
      debugPrint('[OmniVerse] ${service.label} raw result: ${result?.toString().substring(0, (result.toString().length).clamp(0, 300))}');

      if (result == null || result.toString() == 'null') {
        debugPrint('[OmniVerse] ${service.label}: null result');
        return [];
      }

      final String jsonString = result is String ? result : result.toString();

      if (jsonString.isEmpty || jsonString == '[]') {
        debugPrint('[OmniVerse] ${service.label}: empty array');
        return [];
      }

      final List<dynamic> jsonList = json.decode(jsonString);
      debugPrint('[OmniVerse] ${service.label}: found ${jsonList.length} posts');

      final posts = jsonList
          .map((j) => Post.fromJson(j as Map<String, dynamic>, service))
          .toList();

      onPostsScraped?.call(posts, service);
      return posts;
    } catch (e, st) {
      debugPrint('[OmniVerse] ${service.label} scrape error: $e');
      debugPrint('[OmniVerse] $st');
      return [];
    }
  }

  Future<void> disposeAll() async {
    _controllers.clear();
  }
}

import '../models/sns_service.dart';
import 'scraper_service.dart';

class BlueskyScraper implements ScraperService {
  @override
  SnsService get service => SnsService.bluesky;

  @override
  String get scrapingScript => '''
(function() {
  try {
    var posts = [];

    // Helper: parse relative time to ISO date
    // Supports: "3h", "5m", "2d", "1s", "34分", "2時間", "3日", "just now", "now"
    function relativeToISO(text) {
      if (!text || typeof text !== 'string') return '';
      text = text.trim().toLowerCase();
      var now = Date.now();
      var match;

      // English: 3s, 5m, 2h, 1d
      match = text.match(/^(\\d+)\\s*s\$/);
      if (match) return new Date(now - parseInt(match[1]) * 1000).toISOString();
      match = text.match(/^(\\d+)\\s*m\$/);
      if (match) return new Date(now - parseInt(match[1]) * 60000).toISOString();
      match = text.match(/^(\\d+)\\s*h\$/);
      if (match) return new Date(now - parseInt(match[1]) * 3600000).toISOString();
      match = text.match(/^(\\d+)\\s*d\$/);
      if (match) return new Date(now - parseInt(match[1]) * 86400000).toISOString();

      // Japanese: 34分, 2時間, 3日, 10秒
      match = text.match(/^(\\d+)\\s*秒/);
      if (match) return new Date(now - parseInt(match[1]) * 1000).toISOString();
      match = text.match(/^(\\d+)\\s*分/);
      if (match) return new Date(now - parseInt(match[1]) * 60000).toISOString();
      match = text.match(/^(\\d+)\\s*時間/);
      if (match) return new Date(now - parseInt(match[1]) * 3600000).toISOString();
      match = text.match(/^(\\d+)\\s*日/);
      if (match) return new Date(now - parseInt(match[1]) * 86400000).toISOString();

      if (text === 'now' || text === 'just now' || text === 'たった今') {
        return new Date(now).toISOString();
      }

      return '';
    }

    // Find feed items
    var postElements = document.querySelectorAll('[data-testid*="feedItem"]');
    if (postElements.length === 0) {
      postElements = document.querySelectorAll('[data-testid="postThreadItem"]');
    }
    if (postElements.length === 0) {
      var textEls = document.querySelectorAll('[data-testid="postText"]');
      var containers = [];
      textEls.forEach(function(el) {
        var parent = el;
        for (var i = 0; i < 10; i++) {
          parent = parent.parentElement;
          if (!parent) break;
        }
        if (parent) containers.push(parent);
      });
      if (containers.length > 0) postElements = containers;
    }

    postElements.forEach(function(item, index) {
      try {
        var textEl = item.querySelector('[data-testid="postText"]');
        var body = textEl ? textEl.innerText : '';

        var links = item.querySelectorAll('a[href*="/profile/"]');
        var username = '';
        var handle = '';
        for (var li = 0; li < links.length; li++) {
          var link = links[li];
          var href = link.getAttribute('href') || '';
          if (href.match(/\\/profile\\/[^/]+\\/post\\//)) continue;
          var profileMatch = href.match(/\\/profile\\/([^/?]+)/);
          if (profileMatch) {
            if (!handle) handle = '@' + profileMatch[1];
            var linkText = link.textContent || '';
            linkText = linkText.trim();
            if (linkText && !linkText.startsWith('@') && !username) {
              username = linkText;
            }
          }
        }

        var avatarEl = item.querySelector('img[src*="avatar"]');
        var avatarUrl = avatarEl ? avatarEl.getAttribute('src') : null;

        // Extract timestamp from the post link text
        var timestamp = '';
        var postLinks = item.querySelectorAll('a[href*="/post/"]');
        var postId = 'bsky_' + index;

        for (var pi = 0; pi < postLinks.length; pi++) {
          var pl = postLinks[pi];
          var plHref = pl.getAttribute('href') || '';

          // Extract post ID
          var idMatch = plHref.match(/\\/post\\/([^?/]+)/);
          if (idMatch) postId = 'bsky_' + idMatch[1];

          // The time text is typically the content of the post link
          // or a nearby element. Check the link text first.
          var plText = (pl.textContent || '').trim();
          if (plText && !timestamp) {
            var t = relativeToISO(plText);
            if (t) timestamp = t;
          }

          // Also check aria-label
          var aria = pl.getAttribute('aria-label') || '';
          if (aria && !timestamp) {
            var t2 = relativeToISO(aria);
            if (t2) timestamp = t2;
          }
        }

        // Fallback: search all elements for short time-like text
        if (!timestamp) {
          var allEls = item.querySelectorAll('a, span, div, p');
          for (var ei = 0; ei < allEls.length; ei++) {
            var elText = '';
            // Get direct text only (not children)
            var childNodes = allEls[ei].childNodes;
            for (var cn = 0; cn < childNodes.length; cn++) {
              if (childNodes[cn].nodeType === 3) {
                elText += childNodes[cn].textContent;
              }
            }
            elText = elText.trim();
            if (elText) {
              var t3 = relativeToISO(elText);
              if (t3) { timestamp = t3; break; }
            }
          }
        }

        if (body) {
          posts.push({
            id: postId,
            username: username,
            handle: handle,
            body: body,
            timestamp: timestamp,
            avatarUrl: avatarUrl
          });
        }
      } catch(e) {}
    });
    return JSON.stringify(posts);
  } catch(e) {
    return '[]';
  }
})();
''';
}

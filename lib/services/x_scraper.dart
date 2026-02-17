import '../models/sns_service.dart';
import 'scraper_service.dart';

class XScraper implements ScraperService {
  @override
  SnsService get service => SnsService.x;

  @override
  String get scrapingScript => '''
(function() {
  try {
    var posts = [];
    var articles = document.querySelectorAll('article[data-testid="tweet"]');
    articles.forEach(function(article) {
      try {
        var textEl = article.querySelector('[data-testid="tweetText"]');
        var body = textEl ? textEl.innerText : '';

        var timeEl = article.querySelector('time[datetime]');
        var timestamp = timeEl ? timeEl.getAttribute('datetime') : '';

        var userNameEl = article.querySelector('[data-testid="User-Name"]');
        var username = '';
        var handle = '';
        if (userNameEl) {
          var spans = userNameEl.querySelectorAll('span');
          for (var i = 0; i < spans.length; i++) {
            var text = spans[i].innerText.trim();
            if (text.startsWith('@')) {
              handle = text;
            } else if (text.length > 0 && !text.match(/^[·\\d\\s]+\$/) && username === '') {
              username = text;
            }
          }
        }

        var avatarEl = article.querySelector('img[src*="profile_images"]');
        var avatarUrl = avatarEl ? avatarEl.src : null;

        var linkEl = article.querySelector('a[href*="/status/"]');
        var id = '';
        if (linkEl) {
          var match = linkEl.href.match(/status\\/(\\d+)/);
          if (match) id = 'x_' + match[1];
        }

        if (body && id) {
          posts.push({
            id: id,
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

enum SnsService {
  x(
    label: 'X',
    homeUrl: 'https://x.com/home',
    domain: 'x.com',
  ),
  bluesky(
    label: 'Bluesky',
    homeUrl: 'https://bsky.app/',
    domain: 'bsky.app',
  );

  const SnsService({
    required this.label,
    required this.homeUrl,
    required this.domain,
  });

  final String label;
  final String homeUrl;
  final String domain;
}

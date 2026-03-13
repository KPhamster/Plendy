/// Centralized URL validation to prevent SSRF attacks.
///
/// All outbound HTTP requests should validate URLs against this allowlist
/// before fetching. This prevents attackers from supplying URLs pointing
/// to internal services, cloud metadata endpoints, or other sensitive hosts.
class UrlValidator {
  UrlValidator._();

  static const Duration defaultTimeout = Duration(seconds: 10);

  static const Set<String> _allowedDomains = {
    // Yelp
    'yelp.com',
    'www.yelp.com',
    'm.yelp.com',
    // Instagram
    'instagram.com',
    'www.instagram.com',
    // Facebook
    'facebook.com',
    'www.facebook.com',
    'm.facebook.com',
    'fb.com',
    'l.facebook.com',
    // TikTok
    'tiktok.com',
    'www.tiktok.com',
    'vm.tiktok.com',
    'm.tiktok.com',
    // YouTube
    'youtube.com',
    'www.youtube.com',
    'm.youtube.com',
    'youtu.be',
    // Google Maps
    'google.com',
    'www.google.com',
    'maps.google.com',
    'maps.app.goo.gl',
    'goo.gl',
    // Twitter / X
    'twitter.com',
    'www.twitter.com',
    'x.com',
    'www.x.com',
    't.co',
    // Reddit
    'reddit.com',
    'www.reddit.com',
    'old.reddit.com',
    // Pinterest
    'pinterest.com',
    'www.pinterest.com',
    'pin.it',
    // Foursquare / Swarm
    'foursquare.com',
    'www.foursquare.com',
    // Tripadvisor
    'tripadvisor.com',
    'www.tripadvisor.com',
    // Link shorteners commonly used by these services
    'bit.ly',
    'tinyurl.com',
    'ow.ly',
  };

  /// Returns true if the URL's host is on the allowlist.
  ///
  /// Matches exact domain or any subdomain of an allowed domain
  /// (e.g. `en.yelp.com` matches `yelp.com`).
  static bool isAllowedUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final host = uri.host.toLowerCase();

      if (host.isEmpty) return false;

      final scheme = uri.scheme.toLowerCase();
      if (scheme != 'http' && scheme != 'https') return false;

      for (final domain in _allowedDomains) {
        if (host == domain || host.endsWith('.$domain')) {
          return true;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Validates that a URL targets a Yelp domain specifically.
  static bool isYelpUrl(String url) {
    try {
      final host = Uri.parse(url).host.toLowerCase();
      return host == 'yelp.com' ||
          host.endsWith('.yelp.com');
    } catch (_) {
      return false;
    }
  }

  /// Validates that a URL targets a TikTok domain specifically.
  static bool isTikTokUrl(String url) {
    try {
      final host = Uri.parse(url).host.toLowerCase();
      return host == 'tiktok.com' ||
          host.endsWith('.tiktok.com');
    } catch (_) {
      return false;
    }
  }
}

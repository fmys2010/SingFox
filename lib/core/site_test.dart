import 'dart:async';
import 'dart:io';
import 'dart:ui' show Color;

/// A site on the overview's latency board.
class Site {
  const Site(this.name, this.icon, this.url, this.color);
  final String name, icon, url;
  final Color color;

  static const all = [
    Site('Google', 'assets/sites/google.png', 'https://www.google.com/generate_204', Color(0xFF4C8DF6)),
    Site('YouTube', 'assets/sites/youtube.png', 'https://www.youtube.com/generate_204', Color(0xFFF2545B)),
    Site('GitHub', 'assets/sites/github.png', 'https://github.com/', Color(0xFFB4B4BD)),
    Site('Cloudflare', 'assets/sites/cloudflare.png', 'https://www.cloudflare.com/cdn-cgi/trace', Color(0xFFF59A4A)),
    Site('BiliBili', 'assets/sites/bilibili.png', 'https://www.bilibili.com/', Color(0xFFF77FA6)),
    Site('字节跳动', 'assets/sites/bytedance.png', 'https://www.bytedance.com/', Color(0xFF4FD1C5)),
  ];
}

/// Time to the response headers of a HEAD request sent through the local
/// mixed inbound, so each site follows the routing rules like a browser
/// would. Returns milliseconds, or -1 on failure or timeout.
Future<int> probeSite(Site site, int mixedPort, {Duration timeout = const Duration(seconds: 6)}) async {
  final client = HttpClient()
    ..findProxy = ((_) => 'PROXY 127.0.0.1:$mixedPort')
    ..connectionTimeout = timeout
    ..userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) SingFox';
  final watch = Stopwatch()..start();
  try {
    final req = await client.openUrl('HEAD', Uri.parse(site.url)).timeout(timeout);
    req.followRedirects = false;
    final res = await req.close().timeout(timeout);
    final ms = watch.elapsedMilliseconds;
    unawaited(res.drain<void>().catchError((_) {}));
    return ms;
  } catch (_) {
    return -1;
  } finally {
    client.close(force: true);
  }
}

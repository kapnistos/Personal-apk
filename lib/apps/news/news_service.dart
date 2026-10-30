import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../../core/settings.dart';

/// A news feed (RSS or Atom) and the topic it belongs to.
class NewsSource {
  const NewsSource(this.name, this.url, this.topic, {this.on = true});
  final String name;
  final String url;
  final String topic;
  final bool on;

  NewsSource copyWith({bool? on}) => NewsSource(name, url, topic, on: on ?? this.on);

  Map<String, dynamic> toJson() => {'name': name, 'url': url, 'topic': topic, 'on': on};

  static NewsSource fromJson(Map<String, dynamic> j) =>
      NewsSource(j['name'] as String, j['url'] as String, j['topic'] as String, on: j['on'] as bool? ?? true);
}

const newsTopics = [
  'General',
  'Netherlands',
  'Greece',
  'Politics',
  'AI',
  'Tech',
  'Investing',
  'Economy',
  'Sports',
  'Science',
];

/// Free, public feeds from established newsrooms. Edit them in News → Sources.
const defaultNewsSources = [
  NewsSource('BBC World', 'https://feeds.bbci.co.uk/news/world/rss.xml', 'General'),
  NewsSource('The Guardian', 'https://www.theguardian.com/world/rss', 'General'),
  NewsSource('NOS', 'https://feeds.nos.nl/nosnieuwsalgemeen', 'Netherlands'),
  NewsSource('NL Times', 'https://nltimes.nl/rss', 'Netherlands'),
  NewsSource('Greek Reporter', 'https://greekreporter.com/feed/', 'Greece'),
  NewsSource('ERT News', 'https://www.ertnews.gr/feed/', 'Greece'),
  NewsSource('Politico Europe', 'https://www.politico.eu/feed/', 'Politics'),
  NewsSource('BBC Politics', 'https://feeds.bbci.co.uk/news/politics/rss.xml', 'Politics'),
  NewsSource('Guardian Politics', 'https://www.theguardian.com/politics/rss', 'Politics'),
  NewsSource('The Verge AI', 'https://www.theverge.com/rss/ai-artificial-intelligence/index.xml', 'AI'),
  NewsSource('Ars Technica AI', 'https://arstechnica.com/ai/feed/', 'AI'),
  NewsSource('MIT Technology Review AI', 'https://www.technologyreview.com/topic/artificial-intelligence/feed', 'AI'),
  NewsSource('Ars Technica', 'https://feeds.arstechnica.com/arstechnica/index', 'Tech'),
  NewsSource('Hacker News', 'https://hnrss.org/frontpage?points=200', 'Tech'),
  NewsSource('CNBC Investing', 'https://www.cnbc.com/id/15839069/device/rss/rss.html', 'Investing'),
  NewsSource('MarketWatch', 'https://feeds.marketwatch.com/marketwatch/topstories/', 'Investing'),
  NewsSource('CNBC Markets', 'https://www.cnbc.com/id/100003114/device/rss/rss.html', 'Investing'),
  NewsSource('CNBC Economy', 'https://www.cnbc.com/id/20910258/device/rss/rss.html', 'Economy'),
  NewsSource('Guardian Economics', 'https://www.theguardian.com/business/economics/rss', 'Economy'),
  NewsSource('BBC Business', 'https://feeds.bbci.co.uk/news/business/rss.xml', 'Economy'),
  NewsSource('BBC Sport', 'https://feeds.bbci.co.uk/sport/rss.xml', 'Sports'),
  NewsSource('BBC Athletics', 'https://feeds.bbci.co.uk/sport/athletics/rss.xml', 'Sports'),
  NewsSource('BBC Science', 'https://feeds.bbci.co.uk/news/science_and_environment/rss.xml', 'Science'),
];

/// Older topic names, so feeds saved before the topics changed still land somewhere.
const _renamedTopics = {'World': 'General', 'Tech & AI': 'Tech', 'Markets': 'Investing'};

class NewsItem {
  NewsItem({
    required this.title,
    required this.link,
    required this.source,
    required this.topic,
    this.summary = '',
    this.published,
    this.image,
  });

  final String title;
  final String link;
  final String source;
  final String topic;
  final String summary;
  final DateTime? published;
  final String? image;

  Map<String, dynamic> toJson() => {
    'title': title,
    'link': link,
    'source': source,
    'topic': topic,
    'summary': summary,
    'published': published?.millisecondsSinceEpoch,
    'image': image,
  };

  static NewsItem fromJson(Map<String, dynamic> j) => NewsItem(
    title: j['title'] as String,
    link: j['link'] as String,
    source: j['source'] as String,
    topic: j['topic'] as String,
    summary: j['summary'] as String? ?? '',
    published: j['published'] == null ? null : DateTime.fromMillisecondsSinceEpoch(j['published'] as int),
    image: j['image'] as String?,
  );
}

const _months = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6, //
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

/// Reads RSS dates ("Fri, 30 Oct 2026 07:12:00 +0100" or "GMT") and ISO dates.
DateTime? parseFeedDate(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final s = raw.trim();
  final iso = DateTime.tryParse(s);
  if (iso != null) return iso.toLocal();
  final m = RegExp(
    r'(\d{1,2})\s+([A-Za-z]{3})[a-z]*\s+(\d{4})\s+(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([+-]\d{4}|[A-Z]{1,4})?',
  ).firstMatch(s);
  if (m == null) return null;
  final month = _months[m[2]!.toLowerCase()];
  if (month == null) return null;
  var d = DateTime.utc(
    int.parse(m[3]!),
    month,
    int.parse(m[1]!),
    int.parse(m[4]!),
    int.parse(m[5]!),
    int.parse(m[6] ?? '0'),
  );
  final zone = m[7];
  if (zone != null && (zone.startsWith('+') || zone.startsWith('-'))) {
    final sign = zone.startsWith('-') ? -1 : 1;
    final mins = int.parse(zone.substring(1, 3)) * 60 + int.parse(zone.substring(3, 5));
    d = d.subtract(Duration(minutes: sign * mins));
  } else if (zone != null) {
    const zones = {'EST': -5, 'EDT': -4, 'CST': -6, 'CDT': -5, 'PST': -8, 'PDT': -7, 'CET': 1, 'CEST': 2};
    d = d.subtract(Duration(hours: zones[zone] ?? 0));
  }
  return d.toLocal();
}

String _plain(String html) => html
    .replaceAll(RegExp(r'<[^>]+>'), ' ')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&#8217;', '’')
    .replaceAll('&#8216;', '‘')
    .replaceAll('&#8220;', '“')
    .replaceAll('&#8221;', '”')
    .replaceAll('&#8211;', '–')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Items from an RSS 2.0 or Atom document.
List<NewsItem> parseFeed(String body, NewsSource source) {
  final doc = XmlDocument.parse(body);
  String? text(XmlElement e, String name) => e.findElements(name).firstOrNull?.innerText.trim();
  final out = <NewsItem>[];
  for (final item in doc.findAllElements('item')) {
    final title = text(item, 'title');
    final link = text(item, 'link');
    if (title == null || link == null || title.isEmpty) continue;
    final image =
        item.findElements('media:thumbnail').firstOrNull?.getAttribute('url') ??
        item.findElements('media:content').firstOrNull?.getAttribute('url') ??
        item
            .findElements('enclosure')
            .where((e) => (e.getAttribute('type') ?? '').startsWith('image'))
            .firstOrNull
            ?.getAttribute('url');
    out.add(
      NewsItem(
        title: _plain(title),
        link: link,
        source: source.name,
        topic: source.topic,
        summary: _plain(text(item, 'description') ?? ''),
        published: parseFeedDate(text(item, 'pubDate') ?? text(item, 'dc:date')),
        image: image,
      ),
    );
  }
  for (final entry in doc.findAllElements('entry')) {
    final title = text(entry, 'title');
    final links = entry.findElements('link').toList();
    final link =
        (links.where((l) => (l.getAttribute('rel') ?? 'alternate') == 'alternate').firstOrNull ?? links.firstOrNull)
            ?.getAttribute('href');
    if (title == null || link == null) continue;
    out.add(
      NewsItem(
        title: _plain(title),
        link: link,
        source: source.name,
        topic: source.topic,
        summary: _plain(text(entry, 'summary') ?? text(entry, 'content') ?? ''),
        published: parseFeedDate(text(entry, 'published') ?? text(entry, 'updated')),
      ),
    );
  }
  return out;
}

/// Parses fetched feeds on a background isolate. Null marks a feed that could not be read.
Future<List<List<NewsItem>?>> _parseInBackground(List<(NewsSource, String)> feeds) => Isolate.run(
  () => [
    for (final (src, body) in feeds)
      () {
        try {
          return parseFeed(body, src).take(25).toList();
        } catch (_) {
          return null;
        }
      }(),
  ],
);

/// Loads every enabled feed, newest first, and keeps a copy for offline reading.
class NewsService {
  NewsService._();
  static final instance = NewsService._();

  List<NewsItem> items = [];
  DateTime? fetchedAt;
  final failed = <String>[];

  List<NewsSource> sources(AppSettings s) {
    final raw = s.raw('news.sources');
    if (raw == null) return defaultNewsSources;
    try {
      final saved = [
        for (final j in jsonDecode(raw) as List)
          () {
            final x = NewsSource.fromJson((j as Map).cast<String, dynamic>());
            final topic = _renamedTopics[x.topic];
            return topic == null ? x : NewsSource(x.name, x.url, topic, on: x.on);
          }(),
      ];
      // Feeds added to the defaults later appear for everyone, switched on.
      final known = {for (final x in saved) x.url};
      return [...saved, ...defaultNewsSources.where((d) => !known.contains(d.url))];
    } catch (_) {
      return defaultNewsSources;
    }
  }

  Future<void> saveSources(AppSettings s, List<NewsSource> list) =>
      s.setRaw('news.sources', jsonEncode([for (final x in list) x.toJson()]));

  void loadCache(AppSettings s) {
    if (items.isNotEmpty) return;
    final raw = s.raw('news.cache');
    if (raw == null) return;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      fetchedAt = DateTime.fromMillisecondsSinceEpoch(j['at'] as int);
      items = [for (final i in j['items'] as List) NewsItem.fromJson((i as Map).cast<String, dynamic>())];
    } catch (_) {}
  }

  bool get stale => fetchedAt == null || DateTime.now().difference(fetchedAt!) > const Duration(minutes: 30);

  Future<void>? _refreshing;

  /// Fetches every enabled feed. Calls made while one is running share it.
  Future<void> refresh(AppSettings s) => _refreshing ??= _refresh(s).whenComplete(() => _refreshing = null);

  Future<void> _refresh(AppSettings s) async {
    final enabled = sources(s).where((x) => x.on).toList();
    final failedNow = <String>[];
    final bodies = await Future.wait(
      enabled.map((src) async {
        try {
          final res = await http
              .get(Uri.parse(src.url), headers: {'User-Agent': 'Mozilla/5.0 (Hub news reader)'})
              .timeout(const Duration(seconds: 12));
          if (res.statusCode != 200) throw 'HTTP ${res.statusCode}';
          return (src, utf8.decode(res.bodyBytes, allowMalformed: true));
        } catch (_) {
          failedNow.add(src.name);
          return null;
        }
      }),
    );
    final fetched = bodies.nonNulls.toList();
    // XML parsing of a dozen feeds takes long enough to stutter scrolling, so it runs on its own isolate.
    final parsed = fetched.isEmpty ? <List<NewsItem>?>[] : await _parseInBackground(fetched);
    for (var i = 0; i < fetched.length; i++) {
      if (parsed[i] == null) failedNow.add(fetched[i].$1.name);
    }
    failed
      ..clear()
      ..addAll(failedNow);
    final all = [for (final r in parsed) ...?r];
    if (all.isEmpty && items.isNotEmpty) return; // Offline: keep what we had.
    // The same story from two feeds shows once.
    final seen = <String>{};
    all.removeWhere((i) => !seen.add(i.title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')));
    all.sort((a, b) => (b.published ?? DateTime(2000)).compareTo(a.published ?? DateTime(2000)));
    items = all;
    fetchedAt = DateTime.now();
    // A cache, not a preference: saved quietly so screens reading settings don't redraw.
    await s.setRaw(
      'news.cache',
      jsonEncode({
        'at': fetchedAt!.millisecondsSinceEpoch,
        'items': [for (final i in all.take(250)) i.toJson()],
      }),
      quiet: true,
    );
  }

  /// The few stories to know right now: the newest from each topic, then the rest by time.
  List<NewsItem> briefing({int perTopic = 2, int max = 8}) {
    final cutoff = DateTime.now().subtract(const Duration(hours: 36));
    final fresh = items.where((i) => i.published == null || i.published!.isAfter(cutoff)).toList();
    final out = <NewsItem>[];
    for (final t in newsTopics) {
      out.addAll(fresh.where((i) => i.topic == t).take(perTopic));
    }
    out.sort((a, b) => (b.published ?? DateTime(2000)).compareTo(a.published ?? DateTime(2000)));
    return out.take(max).toList();
  }
}

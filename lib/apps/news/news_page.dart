import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/format.dart';
import '../../core/press.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../claude/claude_bridge.dart';
import 'news_service.dart';

const newsColor = Color(0xFF8A5A44);

Future<void> openArticle(String link) =>
    launchUrl(Uri.parse(link), mode: LaunchMode.inAppBrowserView).catchError((_) => false);

class NewsPage extends StatefulWidget {
  const NewsPage({super.key});

  @override
  State<NewsPage> createState() => _NewsPageState();
}

class _NewsPageState extends State<NewsPage> {
  final _news = NewsService.instance;
  String _topic = 'Briefing';
  bool _loading = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _news.loadCache(context.settings);
    if (_news.stale && !_loading) {
      _loading = true;
      _load();
    }
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() => _loading = true);
    await _load();
  }

  Future<void> _load() async {
    try {
      await _news.refresh(context.settings);
    } catch (_) {
      // Feeds report their own failures; anything else just leaves the old list.
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final items = switch (_topic) {
      'Briefing' => _news.briefing(),
      'Latest' => _news.items.take(80).toList(),
      _ => _news.items.where((i) => i.topic == _topic).take(60).toList(),
    };
    return Scaffold(
      appBar: HubBar(
        title: const Text('News'),
        actions: [
          IconButton(
            tooltip: 'Summarise with Claude',
            icon: const Icon(Icons.auto_awesome_outlined),
            onPressed: _news.items.isEmpty
                ? null
                : () => ClaudeBridge.ask(
                    context,
                    'Give me a short briefing of what matters today, from these headlines. '
                    'Group by topic and say why each matters to someone living in the Netherlands with ties to Greece.\n\n'
                    '${_news.briefing(perTopic: 4, max: 24).map((i) => '- [${i.topic}] ${i.title} (${i.source})').join('\n')}',
                  ),
          ),
          IconButton(
            tooltip: 'Sources',
            icon: const Icon(Icons.tune_rounded),
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NewsSourcesPage()));
              _refresh();
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: Builder(
          builder: (context) {
            final header = <Widget>[
              PillTabs<String>(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                options: [
                  for (final t in ['Briefing', 'Latest', ...newsTopics]) (t, t),
                ],
                value: _topic,
                onChanged: (t) => setState(() => _topic = t),
              ),
              if (_loading) const LinearProgressIndicator(minHeight: 2, color: newsColor),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Text(
                  [
                    if (_news.fetchedAt != null) 'Updated ${relativeTime(_news.fetchedAt!)}',
                    if (_news.failed.isNotEmpty) 'could not load ${_news.failed.join(', ')}',
                    if (_topic == 'Briefing') 'the newest stories from each topic',
                  ].join(' · '),
                  style: TextStyle(color: p.muted, fontSize: 13),
                ),
              ),
              if (items.isEmpty && !_loading)
                EmptyState(
                  icon: Icons.cloud_off_rounded,
                  title: 'No news yet',
                  message: _news.failed.isEmpty
                      ? 'Pull down to load the latest headlines.'
                      : 'Check your connection and pull down to try again.',
                ),
            ];
            // Built lazily: the full list can hold a hundred stories with pictures.
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 32),
              itemCount: header.length + items.length,
              itemBuilder: (context, index) {
                if (index < header.length) return header[index];
                final i = index - header.length;
                return ContentWidth(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                    child: i == 0 && items[i].image != null ? _LeadStory(item: items[i]) : NewsTile(item: items[i]),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _LeadStory extends StatelessWidget {
  const _LeadStory({required this.item});
  final NewsItem item;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Press(
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openArticle(item.link),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: LayoutBuilder(
                  builder: (context, box) => Image.network(
                    item.image!,
                    fit: BoxFit.cover,
                    cacheWidth: box.maxWidth.isFinite
                        ? (box.maxWidth * MediaQuery.devicePixelRatioOf(context)).round().clamp(1, 1600)
                        : null,
                    errorBuilder: (_, _, _) => Container(color: p.raised),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Byline(item: item),
                    const SizedBox(height: 6),
                    Text(item.title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, height: 1.25)),
                    if (item.summary.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        item.summary,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.muted, height: 1.4),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Byline extends StatelessWidget {
  const _Byline({required this.item});
  final NewsItem item;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Text(
      [item.source, item.topic, if (item.published != null) relativeTime(item.published!)].join('  ·  '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 12, letterSpacing: 0.4, color: p.muted, fontWeight: FontWeight.w600),
    );
  }
}

class NewsTile extends StatelessWidget {
  const NewsTile({super.key, required this.item, this.compact = false});
  final NewsItem item;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Press(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => openArticle(item.link),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: compact ? 6 : 8, horizontal: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Byline(item: item),
                    const SizedBox(height: 3),
                    Text(
                      item.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: compact ? 14.5 : 15.5, fontWeight: FontWeight.w600, height: 1.3),
                    ),
                    if (!compact && item.summary.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        item.summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.muted, fontSize: 14),
                      ),
                    ],
                  ],
                ),
              ),
              if (item.image != null && !compact) ...[
                const SizedBox(width: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    item.image!,
                    width: 84,
                    height: 64,
                    fit: BoxFit.cover,
                    cacheWidth: (84 * MediaQuery.devicePixelRatioOf(context)).round(),
                    errorBuilder: (_, _, _) => const SizedBox(width: 84),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class NewsSourcesPage extends StatefulWidget {
  const NewsSourcesPage({super.key});

  @override
  State<NewsSourcesPage> createState() => _NewsSourcesPageState();
}

class _NewsSourcesPageState extends State<NewsSourcesPage> {
  late List<NewsSource> _list = NewsService.instance.sources(context.settings);

  Future<void> _save() => NewsService.instance.saveSources(context.settings, _list);

  Future<void> _add() async {
    final name = TextEditingController();
    final url = TextEditingController();
    var topic = newsTopics.first;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Add a feed'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: url,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(labelText: 'RSS or Atom link'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: topic,
                decoration: const InputDecoration(labelText: 'Topic'),
                items: [for (final t in newsTopics) DropdownMenuItem(value: t, child: Text(t))],
                onChanged: (v) => setState(() => topic = v ?? topic),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
          ],
        ),
      ),
    );
    if (ok == true && url.text.trim().isNotEmpty) {
      setState(
        () => _list = [
          ..._list,
          NewsSource(
            name.text.trim().isEmpty ? Uri.parse(url.text.trim()).host : name.text.trim(),
            url.text.trim(),
            topic,
          ),
        ],
      );
      await _save();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Scaffold(
      appBar: HubBar(
        title: const Text('News sources'),
        actions: [
          TextButton(
            onPressed: () async {
              setState(() => _list = defaultNewsSources);
              await _save();
            },
            child: const Text('Reset'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(onPressed: _add, child: const Icon(Icons.add_rounded)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
        children: [
          for (final t in newsTopics)
            if (_list.any((s) => s.topic == t))
              ContentWidth(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: GroupSection(
                    title: t,
                    child: Column(
                      children: [
                        for (final s in _list.where((s) => s.topic == t))
                          SwitchListTile(
                            title: Text(s.name),
                            subtitle: Text(Uri.tryParse(s.url)?.host ?? s.url, style: TextStyle(color: p.muted)),
                            value: s.on,
                            onChanged: (v) async {
                              setState(() => _list = [for (final x in _list) identical(x, s) ? x.copyWith(on: v) : x]);
                              await _save();
                            },
                            secondary: defaultNewsSources.any((d) => d.url == s.url)
                                ? null
                                : IconButton(
                                    tooltip: 'Remove',
                                    icon: const Icon(Icons.close_rounded),
                                    onPressed: () async {
                                      setState(() => _list = _list.where((x) => !identical(x, s)).toList());
                                      await _save();
                                    },
                                  ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
          Text(
            'Any site with an RSS or Atom feed works. Hub reads them directly; nothing goes through a server.',
            style: TextStyle(color: p.muted, fontSize: 13.5),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// A link on the home screen that jumps straight into another app or site.
class Shortcut {
  const Shortcut(this.name, this.url, this.color, {this.appUrl, this.label});

  final String name;

  /// Opened in the browser when the app is not installed (and on desktop).
  final String url;
  final int color;

  /// The app's own link (instagram://), tried first on phones.
  final String? appUrl;

  /// One or two letters on the tile; the first letter of [name] when empty.
  final String? label;

  String get glyph => (label ?? name.characters.first).toUpperCase();

  Map<String, dynamic> toJson() => {
    'name': name,
    'url': url,
    'color': color,
    if (appUrl != null) 'app': appUrl,
    if (label != null) 'label': label,
  };

  static Shortcut fromJson(Map<String, dynamic> j) => Shortcut(
    j['name'] as String,
    j['url'] as String,
    j['color'] as int? ?? 0xFF5F6B7A,
    appUrl: j['app'] as String?,
    label: j['label'] as String?,
  );
}

/// Ready-made shortcuts. Each opens the installed app when there is one.
const shortcutCatalog = [
  Shortcut('X', 'https://x.com', 0xFF14171A, appUrl: 'twitter://timeline', label: 'X'),
  Shortcut('Reddit', 'https://www.reddit.com', 0xFFFF4500),
  Shortcut('Instagram', 'https://www.instagram.com', 0xFFC13584, appUrl: 'instagram://app', label: 'Ig'),
  Shortcut('TikTok', 'https://www.tiktok.com', 0xFF111111, appUrl: 'snssdk1233://', label: 'Tt'),
  Shortcut('GitHub', 'https://github.com', 0xFF24292F, label: 'Gh'),
  Shortcut('LinkedIn', 'https://www.linkedin.com', 0xFF0A66C2, appUrl: 'linkedin://', label: 'in'),
  Shortcut('Outlook', 'https://outlook.live.com/mail', 0xFF0F6CBD, appUrl: 'ms-outlook://', label: 'O'),
  Shortcut('Gmail', 'https://mail.google.com', 0xFFD93025, appUrl: 'googlegmail://', label: 'G'),
  Shortcut('Proton Mail', 'https://mail.proton.me', 0xFF6D4AFF, appUrl: 'protonmail://', label: 'P'),
  Shortcut('WhatsApp', 'https://web.whatsapp.com', 0xFF25D366, appUrl: 'whatsapp://', label: 'W'),
  Shortcut('Telegram', 'https://web.telegram.org', 0xFF229ED9, appUrl: 'tg://', label: 'Tg'),
  Shortcut('YouTube', 'https://www.youtube.com', 0xFFFF0033, appUrl: 'vnd.youtube://', label: 'Yt'),
  Shortcut('Spotify', 'https://open.spotify.com', 0xFF1DB954, appUrl: 'spotify:', label: 'S'),
  Shortcut('Facebook', 'https://www.facebook.com', 0xFF1877F2, appUrl: 'fb://', label: 'f'),
  Shortcut('Google Maps', 'https://maps.google.com', 0xFF34A853, label: 'M'),
  Shortcut('Google Drive', 'https://drive.google.com', 0xFF1A73E8, label: 'D'),
  Shortcut('ChatGPT', 'https://chatgpt.com', 0xFF10A37F, label: 'C'),
  Shortcut('Revolut', 'https://app.revolut.com', 0xFF191C1F, appUrl: 'revolut://', label: 'R'),
  Shortcut('ABN AMRO', 'https://www.abnamro.nl/en/personal/internet-banking', 0xFF00716B, label: 'A'),
  Shortcut('Eurobank', 'https://ebanking.eurobank.gr', 0xFFB3122E, label: 'E'),
  Shortcut('ING', 'https://mijn.ing.nl', 0xFFFF6200, label: 'ING'),
  Shortcut('Rabobank', 'https://www.rabobank.nl/particulieren', 0xFF000099, label: 'Ra'),
  Shortcut('bunq', 'https://web.bunq.com', 0xFF3394D7, label: 'b'),
  Shortcut('Wise', 'https://wise.com', 0xFF9FE870, label: 'W'),
  Shortcut('PayPal', 'https://www.paypal.com', 0xFF003087, label: 'Pp'),
  Shortcut('Tikkie', 'https://tikkie.me', 0xFF4C4DDC, label: 'Tk'),
  Shortcut('Piraeus', 'https://www.winbank.gr', 0xFFFFD100, label: 'Pi'),
  Shortcut('DEGIRO', 'https://trader.degiro.nl', 0xFF00A3E0, label: 'DG'),
  Shortcut('Trading 212', 'https://app.trading212.com', 0xFF00A0DC, label: 'T2'),
  Shortcut('Binance', 'https://www.binance.com', 0xFFF0B90B, label: 'Bn'),
  Shortcut('DigiD', 'https://mijn.digid.nl', 0xFFE17000, label: 'Di'),
  Shortcut('Belastingdienst', 'https://mijn.belastingdienst.nl', 0xFF154273, label: 'Bd'),
  Shortcut('DUO', 'https://mijn.duo.nl', 0xFF01689B, label: 'DU'),
  Shortcut('NS', 'https://www.ns.nl/en', 0xFFFFC917, label: 'NS'),
];

/// Starts an activity for [url]; tests swap it for a fake.
typedef UrlLauncher = Future<bool> Function(Uri url, LaunchMode mode);

@visibleForTesting
UrlLauncher shortcutLauncher = (url, mode) => launchUrl(url, mode: mode);

/// Opens the app if it is installed, otherwise the website.
Future<void> openShortcut(Shortcut s) async {
  final launch = shortcutLauncher;
  final app = s.appUrl;
  if (app != null) {
    try {
      if (await launch(Uri.parse(app), LaunchMode.externalNonBrowserApplication)) return;
    } catch (_) {}
  }
  final web = Uri.parse(s.url);
  try {
    // An https link the app has claimed (reddit.com, github.com) opens in the app.
    if (await launch(web, LaunchMode.externalNonBrowserApplication)) return;
  } catch (_) {}
  try {
    await launch(web, LaunchMode.externalApplication);
  } catch (_) {}
}

class ShortcutGlyph extends StatelessWidget {
  const ShortcutGlyph({super.key, required this.shortcut, this.size = 50});
  final Shortcut shortcut;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = Color(shortcut.color);
    final light = c.computeLuminance() > 0.55;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(size * 0.3), color: c),
      child: Text(
        shortcut.glyph.length > 2 ? shortcut.glyph.substring(0, 2) : shortcut.glyph,
        style: TextStyle(
          color: light ? Colors.black87 : Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: size * (shortcut.glyph.length > 1 ? 0.34 : 0.44),
          letterSpacing: -0.3,
        ),
      ),
    );
  }
}

/// Lets the person pick from the catalogue or add any link.
Future<List<Shortcut>?> pickShortcuts(BuildContext context, List<Shortcut> current) {
  return showModalBottomSheet<List<Shortcut>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ShortcutPicker(current: current),
  );
}

class _ShortcutPicker extends StatefulWidget {
  const _ShortcutPicker({required this.current});
  final List<Shortcut> current;

  @override
  State<_ShortcutPicker> createState() => _ShortcutPickerState();
}

class _ShortcutPickerState extends State<_ShortcutPicker> {
  late final List<Shortcut> _list = [...widget.current];

  bool _has(Shortcut s) => _list.any((x) => x.url == s.url);

  Future<void> _custom() async {
    final name = TextEditingController();
    final url = TextEditingController(text: 'https://');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add any app or site'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: url,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Link',
                helperText: 'A web address, or an app link like spotify:',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
        ],
      ),
    );
    final u = url.text.trim();
    if (!mounted || ok != true || u.isEmpty || u == 'https://') return;
    final host = Uri.tryParse(u)?.host ?? '';
    final n = name.text.trim().isNotEmpty ? name.text.trim() : (host.isNotEmpty ? host : u);
    const palette = [0xFF3A78C9, 0xFF1F7A5A, 0xFFC0563F, 0xFF6650AE, 0xFFCF9418, 0xFF2D8C9E];
    setState(() => _list.add(Shortcut(n, u, palette[_list.length % palette.length])));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 4),
              child: Row(
                children: [
                  Expanded(child: Text('Shortcuts', style: Theme.of(context).textTheme.titleLarge)),
                  TextButton.icon(
                    onPressed: _custom,
                    icon: const Icon(Icons.add_link_rounded, size: 18),
                    label: const Text('Other link'),
                  ),
                ],
              ),
            ),
            if (_list.isNotEmpty)
              SizedBox(
                height: 92,
                child: ReorderableListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  onReorderItem: (a, b) => setState(() => _list.insert(b, _list.removeAt(a))),
                  children: [
                    for (final s in _list)
                      Padding(
                        key: ValueKey(s.url),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Column(
                              children: [
                                ShortcutGlyph(shortcut: s, size: 46),
                                const SizedBox(height: 4),
                                SizedBox(
                                  width: 60,
                                  child: Text(
                                    s.name,
                                    maxLines: 1,
                                    textAlign: TextAlign.center,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                            Positioned(
                              right: -2,
                              top: -6,
                              child: GestureDetector(
                                onTap: () => setState(() => _list.remove(s)),
                                child: const CircleAvatar(
                                  radius: 10,
                                  backgroundColor: Colors.black54,
                                  child: Icon(Icons.close_rounded, size: 13, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            const Divider(height: 20),
            Flexible(
              child: GridView.extent(
                shrinkWrap: true,
                maxCrossAxisExtent: 92,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                childAspectRatio: 0.82,
                children: [
                  for (final s in shortcutCatalog)
                    InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => setState(() => _has(s) ? _list.removeWhere((x) => x.url == s.url) : _list.add(s)),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Opacity(
                                opacity: _has(s) ? 1 : 0.85,
                                child: ShortcutGlyph(shortcut: s, size: 46),
                              ),
                              if (_has(s))
                                const Positioned(
                                  right: -4,
                                  bottom: -4,
                                  child: CircleAvatar(
                                    radius: 10,
                                    backgroundColor: Color(0xFF1F7A5A),
                                    child: Icon(Icons.check_rounded, size: 14, color: Colors.white),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          Text(
                            s.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 12.5),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: FilledButton(onPressed: () => Navigator.pop(context, _list), child: const Text('Done')),
            ),
          ],
        ),
      ),
    );
  }
}

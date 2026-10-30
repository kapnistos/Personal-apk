import 'package:flutter/material.dart';

import 'package:flutter/services.dart';

import '../core/reminders.dart';
import '../core/sync/sync_service.dart';
import '../core/settings.dart';
import '../core/theme.dart';
import '../core/widgets.dart';

class MePage extends StatelessWidget {
  const MePage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.settings;
    final p = Palette.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Me')),
      body: ListenableBuilder(
        listenable: s,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            ContentWidth(
              child: Section(
                title: 'Profile',
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: p.accent,
                    child: Text(s.name.isEmpty ? '?' : s.name.characters.first.toUpperCase(),
                        style: TextStyle(color: p.onAccent, fontWeight: FontWeight.w700)),
                  ),
                  title: Text(s.name.isEmpty ? 'Add your name' : s.name),
                  subtitle: const Text('Used for the greeting on Home'),
                  trailing: const Icon(Icons.edit_outlined, size: 20),
                  onTap: () async {
                    final v = await _prompt(context, 'Your name', s.name);
                    if (v != null) s.setName(v);
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            ContentWidth(
              child: Section(
                title: 'Appearance',
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: SegmentedButton<ThemeMode>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: ThemeMode.system, label: Text('System')),
                      ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                      ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                    ],
                    selected: {s.themeMode},
                    onSelectionChanged: (v) => s.setThemeMode(v.first),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            ContentWidth(
              child: Section(
                title: 'Weather',
                child: Column(children: [
                  ListTile(
                    title: const Text('Temperature'),
                    trailing: SegmentedButton<TempUnit>(
                      showSelectedIcon: false,
                      style: SegmentedButton.styleFrom(visualDensity: VisualDensity.compact),
                      segments: const [
                        ButtonSegment(value: TempUnit.celsius, label: Text('°C')),
                        ButtonSegment(value: TempUnit.fahrenheit, label: Text('°F')),
                      ],
                      selected: {s.tempUnit},
                      onSelectionChanged: (v) => s.setTempUnit(v.first),
                    ),
                  ),
                  ListTile(
                    title: const Text('Google Weather key'),
                    subtitle: Text(s.googleWeatherKey.isEmpty
                        ? 'Not set. Using Open-Meteo for the long-term forecast.'
                        : 'Set. Google Weather is used for the forecast.'),
                    trailing: const Icon(Icons.key_rounded, size: 20),
                    onTap: () async {
                      final v = await _prompt(context, 'Google Maps Platform API key', s.googleWeatherKey,
                          help: 'Create a key in Google Cloud with the Weather API enabled. Leave empty to use Open-Meteo.');
                      if (v != null) s.setGoogleWeatherKey(v);
                    },
                  ),
                  const SizedBox(height: 4),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            ContentWidth(
              child: Section(
                title: 'Wallet',
                child: ListTile(
                  title: const Text('Currency'),
                  trailing: DropdownButton<String>(
                    value: s.currency,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final c in const ['EUR', 'USD', 'GBP', 'CHF'])
                        DropdownMenuItem(value: c, child: Text(c)),
                    ],
                    onChanged: (v) => s.setCurrency(v ?? 'EUR'),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const ContentWidth(child: _SyncSection()),
            const SizedBox(height: 16),
            ContentWidth(
              child: Section(
                title: 'Notifications',
                child: ListTile(
                  title: const Text('Allow reminders'),
                  subtitle: Text(Reminders.instance.supported
                      ? 'Needed for to-do and calendar reminders'
                      : 'Not available on this device'),
                  trailing: const Icon(Icons.notifications_active_outlined, size: 20),
                  onTap: () async {
                    final db = context.db;
                    await Reminders.instance.requestPermission();
                    await Reminders.instance.resync(db);
                  },
                ),
              ),
            ),
            const SizedBox(height: 24),
            ContentWidth(
              child: Text(
                'Hub keeps your data on this device. Claude opens in the official Claude app on your own plan; '
                'no paid API is used.',
                textAlign: TextAlign.center,
                style: TextStyle(color: p.muted, fontSize: 13.5, height: 1.45),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<String?> _prompt(BuildContext context, String title, String initial, {String? help}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(controller: c, autofocus: true, onSubmitted: (v) => Navigator.pop(d, v)),
        if (help != null) ...[
          const SizedBox(height: 10),
          Text(help, style: TextStyle(color: Palette.of(d).muted, fontSize: 13.5)),
        ],
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(d, c.text), child: const Text('Save')),
      ],
    ),
  );
}

class _SyncSection extends StatefulWidget {
  const _SyncSection();

  @override
  State<_SyncSection> createState() => _SyncSectionState();
}

class _SyncSectionState extends State<_SyncSection> {
  final _url = TextEditingController();
  final _token = TextEditingController();
  bool _filled = false;
  String? _error;
  bool _busy = false;
  bool _pendingClient = false;
  List<String> _ips = [];

  @override
  void initState() {
    super.initState();
    SyncService.localAddresses().then((a) {
      if (mounted) setState(() => _ips = a);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_filled) return;
    _filled = true;
    final s = context.settings;
    _url.text = s.syncUrl;
    if (s.syncMode == 'client') _token.text = s.syncToken;
  }

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _setMode(String mode) async {
    final s = context.settings;
    setState(() {
      _error = null;
      _pendingClient = false;
    });
    if (mode == 'server') {
      await s.setSync(mode: 'server', token: s.syncToken.isEmpty || s.syncMode != 'server' ? SyncService.newToken() : s.syncToken);
    } else if (mode == 'off') {
      await s.setSync(mode: 'off');
    } else {
      // Show the form; the current mode stays until Connect succeeds.
      setState(() => _pendingClient = true);
    }
  }

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await SyncService.test(_url.text, _token.text);
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _busy = false;
        _error = err;
      });
      return;
    }
    await context.settings.setSync(mode: 'client', url: _url.text, token: _token.text);
    if (mounted) {
      setState(() {
        _busy = false;
        _pendingClient = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.settings;
    final p = Palette.of(context);
    final mode = _pendingClient ? 'client' : s.syncMode;
    return Section(
      title: 'Sync',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'off', label: Text('Off')),
              ButtonSegment(value: 'server', label: Text('Server')),
              ButtonSegment(value: 'client', label: Text('Connect')),
            ],
            selected: {mode},
            onSelectionChanged: (v) => _setMode(v.first),
          ),
          const SizedBox(height: 12),
          if (mode == 'off')
            Text(
              'Sync keeps notes, tasks, calendars and the wallet the same on all your devices, '
              'through your own always-on laptop. Nothing goes to a cloud.',
              style: TextStyle(color: p.muted, height: 1.45),
            ),
          if (mode == 'server') ...[
            Text('Keep Hub open on this laptop. On your phone, choose "Connect" and enter:',
                style: TextStyle(color: p.muted, height: 1.45)),
            const SizedBox(height: 10),
            _copyRow(context, 'Address', _ips.firstOrNull ?? 'this computer\'s IP'),
            _copyRow(context, 'Sync key', s.syncToken),
            if (_ips.length > 1)
              Text('Other addresses: ${_ips.skip(1).join(', ')}', style: TextStyle(color: p.muted, fontSize: 13)),
          ],
          if (mode == 'client') ...[
            TextField(controller: _url, decoration: const InputDecoration(hintText: 'Server address, e.g. 100.101.102.103')),
            const SizedBox(height: 8),
            TextField(controller: _token, decoration: const InputDecoration(hintText: 'Sync key')),
            const SizedBox(height: 10),
            Row(children: [
              FilledButton(
                onPressed: _busy ? null : _connect,
                child: Text(_busy ? 'Checking…' : (s.syncMode == 'client' && !_pendingClient ? 'Save' : 'Connect')),
              ),
              const SizedBox(width: 10),
              if (s.syncMode == 'client')
                OutlinedButton(onPressed: SyncService.instance.syncNow, child: const Text('Sync now')),
            ]),
          ],
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: TextStyle(color: p.danger))),
          if (s.syncMode != 'off')
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: ValueListenableBuilder<String>(
                valueListenable: SyncService.instance.status,
                builder: (context, v, _) => Text(v, style: TextStyle(color: p.muted, fontSize: 13.5)),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _copyRow(BuildContext context, String label, String value) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        SizedBox(width: 72, child: Text(label, style: TextStyle(color: p.muted))),
        Expanded(child: SelectableText(value, style: const TextStyle(fontWeight: FontWeight.w600))),
        IconButton(
          tooltip: 'Copy',
          icon: const Icon(Icons.copy_rounded, size: 18),
          onPressed: () => Clipboard.setData(ClipboardData(text: value)),
        ),
      ]),
    );
  }
}

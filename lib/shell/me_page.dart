import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_info.dart';
import '../core/press.dart';
import '../core/reminders.dart';
import '../core/settings.dart';
import '../core/sync/sync_service.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import 'automations_page.dart';
import 'customize.dart';

class MePage extends StatelessWidget {
  const MePage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.settings;
    final p = Palette.of(context);
    return Scaffold(
      appBar: HubBar(title: const Text('Me')),
      body: ListenableBuilder(
        listenable: s,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            ContentWidth(
              child: GroupSection(
                title: 'Profile',
                child: Press(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: p.accent,
                      child: Text(
                        s.name.isEmpty ? '?' : s.name.characters.first.toUpperCase(),
                        style: TextStyle(color: p.onAccent, fontWeight: FontWeight.w700),
                      ),
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
            ),
            const SizedBox(height: 16),
            ContentWidth(
              child: GroupSection(
                title: 'Appearance',
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: PillToggle<ThemeMode>(
                          options: const [
                            (ThemeMode.system, 'System'),
                            (ThemeMode.light, 'Light'),
                            (ThemeMode.dark, 'Dark'),
                          ],
                          value: s.themeMode,
                          onChanged: s.setThemeMode,
                        ),
                      ),
                      const SizedBox(height: 18),
                      _SubLabel('Accent colour'),
                      ColorDots(
                        colors: [for (final a in accentChoices) a.forBrightness(Theme.of(context).brightness)],
                        labels: [for (final a in accentChoices) a.label],
                        selected: accentChoices.indexOf(accentById(s.raw(accentKey))),
                        onSelected: (i) {
                          HapticFeedback.selectionClick();
                          s.setRaw(accentKey, accentChoices[i].id);
                        },
                      ),
                      const SizedBox(height: 18),
                      _SubLabel('Dark background'),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final e in darkBackgrounds.entries)
                            ChoiceChip(
                              label: Text(e.value),
                              selected: (s.raw(darkBackgroundKey) ?? 'black') == e.key,
                              onSelected: (_) => s.setRaw(darkBackgroundKey, e.key),
                            ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _SubLabel('Text size'),
                      SizedBox(
                        width: double.infinity,
                        child: PillToggle<String>(
                          options: [for (final e in textSizes.entries) (e.key, e.value.$1)],
                          value: textSizes.containsKey(s.raw(textSizeKey)) ? s.raw(textSizeKey)! : 'system',
                          onChanged: (v) => s.setRaw(textSizeKey, v),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('On top of your phone\'s own font size.', style: TextStyle(color: p.muted, fontSize: 13.5)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const ContentWidth(
              child: GroupSection(title: 'Home', child: HomeTopOptions()),
            ),
            const SizedBox(height: 16),
            ContentWidth(
              child: GroupSection(
                title: 'Navigation',
                children: [
                  Press(
                    child: ListTile(
                      leading: const RowIcon(Icons.space_dashboard_outlined),
                      title: const Text('Bottom tabs'),
                      subtitle: Text(tabsSummary(s)),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => showTabsSheet(context),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ContentWidth(
              child: GroupSection(
                title: 'Units and keys',
                children: [
                  ListTile(
                    leading: const RowIcon(Icons.payments_outlined),
                    title: const Text('Currency'),
                    trailing: DropdownButton<String>(
                      value: s.currency,
                      underline: const SizedBox.shrink(),
                      items: [
                        // A currency set elsewhere (sync, a restore) is kept in the list so the menu can show it.
                        for (final c in {'EUR', 'USD', 'GBP', 'CHF', s.currency})
                          DropdownMenuItem(value: c, child: Text(c)),
                      ],
                      onChanged: (v) => s.setCurrency(v ?? 'EUR'),
                    ),
                  ),
                  ListTile(
                    leading: const RowIcon(Icons.thermostat_outlined),
                    title: const Text('Temperature'),
                    trailing: PillToggle<TempUnit>(
                      dense: true,
                      options: const [(TempUnit.celsius, '°C'), (TempUnit.fahrenheit, '°F')],
                      value: s.tempUnit,
                      onChanged: s.setTempUnit,
                    ),
                  ),
                  Press(
                    child: ListTile(
                      leading: const RowIcon(Icons.key_rounded),
                      title: const Text('Google Weather key'),
                      subtitle: Text(
                        s.googleWeatherKey.isEmpty
                            ? 'Not set. Using Open-Meteo for the long-term forecast.'
                            : 'Set. Google Weather is used for the forecast.',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () async {
                        final v = await _prompt(
                          context,
                          'Google Maps Platform API key',
                          s.googleWeatherKey,
                          help: 'Create a key in Google Cloud with the Weather API enabled. Leave empty to use Open-Meteo.',
                        );
                        if (v != null) s.setGoogleWeatherKey(v);
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ContentWidth(
              child: GroupSection(
                title: 'Notifications',
                children: [
                  Press(
                    child: ListTile(
                      leading: const RowIcon(Icons.auto_mode_rounded),
                      title: const Text('Automations'),
                      subtitle: const Text('Morning briefing, end of day, bills, low balance, weekly review'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () =>
                          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AutomationsPage())),
                    ),
                  ),
                  Press(
                    child: ListTile(
                      leading: const RowIcon(Icons.notifications_active_outlined),
                      title: const Text('Allow reminders'),
                      subtitle: Text(
                        Reminders.instance.supported
                            ? 'Needed for task, calendar and automation alerts'
                            : 'Not available on this device',
                      ),
                      onTap: () async {
                        final db = context.db;
                        await Reminders.instance.requestPermission();
                        await Reminders.instance.resync(db);
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ContentWidth(
              child: GroupSection(
                title: 'Your data',
                children: [
                  Press(
                    child: ListTile(
                      leading: const RowIcon(Icons.import_export_rounded),
                      title: const Text('Import and export'),
                      subtitle: const Text('All your data in one file, to keep or move to another device'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BackupPage())),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const ContentWidth(child: _SyncSection()),
            const SizedBox(height: 16),
            ContentWidth(
              child: GroupSection(
                title: 'About',
                children: [
                  ListTile(
                    leading: const RowIcon(Icons.info_outline_rounded),
                    title: const Text('Hub'),
                    subtitle: Text(appVersionLabel),
                    trailing: IconButton(
                      tooltip: 'Copy version',
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      onPressed: () => Clipboard.setData(ClipboardData(text: 'Hub $appVersionLabel')),
                    ),
                  ),
                  Press(
                    child: ListTile(
                      leading: const RowIcon(Icons.description_outlined),
                      title: const Text('Open source licences'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => showLicensePage(
                        context: context,
                        applicationName: 'Hub',
                        applicationVersion: appVersionLabel,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                    child: Text(
                      'Hub keeps your data on this device. The AI tab only sends what you ask, to the model you '
                      'pick: through the Claude app on your plan, or on your own API key.',
                      style: TextStyle(color: p.muted, fontSize: 13.5, height: 1.45),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubLabel extends StatelessWidget {
  const _SubLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 10), child: SectionLabel(text));
}

Future<String?> _prompt(BuildContext context, String title, String initial, {String? help}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(controller: c, autofocus: true, onSubmitted: (v) => Navigator.pop(d, v)),
          if (help != null) ...[
            const SizedBox(height: 10),
            Text(help, style: TextStyle(color: Palette.of(d).muted, fontSize: 13.5)),
          ],
        ],
      ),
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
      await s.setSync(
        mode: 'server',
        token: s.syncToken.isEmpty || s.syncMode != 'server' ? SyncService.newToken() : s.syncToken,
      );
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
    return GroupSection(
      title: 'Sync',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PillToggle<String>(
              options: const [('off', 'Off'), ('server', 'Server'), ('client', 'Connect')],
              value: mode,
              onChanged: _setMode,
            ),
            const SizedBox(height: 12),
            if (mode == 'off')
              Text(
                'Sync keeps notes, tasks, calendars and the wallet the same on all your devices, '
                'through your own always-on laptop. Nothing goes to a cloud.',
                style: TextStyle(color: p.muted, height: 1.45),
              ),
            if (mode == 'server') ...[
              Text(
                'Keep Hub open on this laptop. On your phone, choose "Connect" and enter:',
                style: TextStyle(color: p.muted, height: 1.45),
              ),
              const SizedBox(height: 10),
              _copyRow(context, 'Address', _ips.firstOrNull ?? 'this computer\'s IP'),
              _copyRow(context, 'Sync key', s.syncToken),
              if (_ips.length > 1)
                Text('Other addresses: ${_ips.skip(1).join(', ')}', style: TextStyle(color: p.muted, fontSize: 13)),
            ],
            if (mode == 'client') ...[
              TextField(
                controller: _url,
                decoration: const InputDecoration(hintText: 'Server address, e.g. 100.101.102.103'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _token,
                decoration: const InputDecoration(hintText: 'Sync key'),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  FilledButton(
                    onPressed: _busy ? null : _connect,
                    child: Text(_busy ? 'Checking…' : (s.syncMode == 'client' && !_pendingClient ? 'Save' : 'Connect')),
                  ),
                  const SizedBox(width: 10),
                  if (s.syncMode == 'client')
                    OutlinedButton(onPressed: SyncService.instance.syncNow, child: const Text('Sync now')),
                ],
              ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(_error!, style: TextStyle(color: p.danger)),
              ),
            if (s.syncMode != 'off')
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: ValueListenableBuilder<String>(
                  valueListenable: SyncService.instance.status,
                  builder: (context, v, _) => Text(v, style: TextStyle(color: p.muted, fontSize: 13.5)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _copyRow(BuildContext context, String label, String value) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(label, style: TextStyle(color: p.muted)),
          ),
          Expanded(
            child: SelectableText(value, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          IconButton(
            tooltip: 'Copy',
            icon: const Icon(Icons.copy_rounded, size: 18),
            onPressed: () => Clipboard.setData(ClipboardData(text: value)),
          ),
        ],
      ),
    );
  }
}

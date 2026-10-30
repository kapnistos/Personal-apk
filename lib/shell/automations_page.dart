import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/automations.dart';
import '../core/backup.dart';
import '../core/format.dart';
import '../core/reminders.dart';
import '../core/settings.dart';
import '../core/theme.dart';
import '../core/widgets.dart';

/// Things Hub does on its own: briefings, alerts, reviews, backups.
class AutomationsPage extends StatefulWidget {
  const AutomationsPage({super.key});

  @override
  State<AutomationsPage> createState() => _AutomationsPageState();
}

class _AutomationsPageState extends State<AutomationsPage> {
  List<PlannedNote>? _upcoming;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final list = await planAutomations(context.db);
    list.sort((a, b) => a.at.compareTo(b.at));
    if (mounted) setState(() => _upcoming = list);
  }

  Future<void> _set(String key, String value) async {
    await context.settings.setRaw(key, value);
    await Reminders.instance.ensurePermission();
    await _load();
  }

  Future<void> _pickTime(String key, String current) async {
    final parts = current.split(':');
    final t = await showTimePicker(
      context: context,
      initialTime: parts.length == 2
          ? TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]))
          : const TimeOfDay(hour: 7, minute: 30),
    );
    if (t != null) await _set(key, '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = context.settings;
    final a = AutomationSettings({
      for (final k in [
        'auto.briefing',
        'auto.evening',
        'auto.bills',
        'auto.lowBalance',
        'auto.weekly',
        'auto.overdue',
        'auto.habits',
        'auto.backup',
      ])
        if (s.raw(k) != null) k: s.raw(k)!,
    });
    final briefing = s.raw('auto.briefing') ?? '07:30';
    final evening = s.raw('auto.evening') ?? 'off';
    final threshold = a.lowBalanceCents;

    Widget toggle(String key, bool on, IconData icon, String title, String subtitle, {VoidCallback? onTap}) =>
        SwitchListTile(
          secondary: Icon(icon, color: on ? p.accent : p.muted),
          title: Text(title),
          subtitle: GestureDetector(
            onTap: onTap,
            child: Text(subtitle, style: TextStyle(color: onTap != null && on ? p.accent : p.muted)),
          ),
          value: on,
          onChanged: (v) => _set(key, v ? 'on' : 'off'),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Automations')),
      body: ListenableBuilder(
        listenable: s,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
          children: [
            ContentWidth(
              child: Text(
                'Hub works these out from your own data and shows them as notifications. Nothing leaves your phone.',
                style: TextStyle(color: p.muted),
              ),
            ),
            const SizedBox(height: 12),
            ContentWidth(
              child: Card(
                child: Column(
                  children: [
                    SwitchListTile(
                      secondary: Icon(Icons.wb_twilight_rounded, color: a.briefing != null ? p.accent : p.muted),
                      title: const Text('Morning briefing'),
                      subtitle: GestureDetector(
                        onTap: a.briefing == null ? null : () => _pickTime('auto.briefing', briefing),
                        child: Text(
                          a.briefing == null
                              ? 'Events, tasks, bills, deadlines and habits for the day'
                              : 'Every day at $briefing · tap to change',
                          style: TextStyle(color: a.briefing == null ? p.muted : p.accent),
                        ),
                      ),
                      value: a.briefing != null,
                      onChanged: (v) => _set('auto.briefing', v ? '07:30' : 'off'),
                    ),
                    SwitchListTile(
                      secondary: Icon(Icons.nightlight_outlined, color: a.evening != null ? p.accent : p.muted),
                      title: const Text('End of day summary'),
                      subtitle: GestureDetector(
                        onTap: a.evening == null ? null : () => _pickTime('auto.evening', evening),
                        child: Text(
                          a.evening == null
                              ? 'What you got done and spent, and what tomorrow holds'
                              : 'Every day at $evening · tap to change',
                          style: TextStyle(color: a.evening == null ? p.muted : p.accent),
                        ),
                      ),
                      value: a.evening != null,
                      onChanged: (v) => _set('auto.evening', v ? '21:00' : 'off'),
                    ),
                    toggle(
                      'auto.bills',
                      a.bills,
                      Icons.receipt_long_outlined,
                      'Bill reminders',
                      'The evening before a recurring payment leaves',
                    ),
                    SwitchListTile(
                      secondary: Icon(Icons.trending_down_rounded, color: threshold != null ? p.accent : p.muted),
                      title: const Text('Low balance warning'),
                      subtitle: GestureDetector(
                        onTap: threshold == null ? null : () => _editThreshold(threshold),
                        child: Text(
                          threshold == null
                              ? 'Two days before a card would drop too low'
                              : 'When a card would drop under ${money(threshold, s.currency)} · tap to change',
                          style: TextStyle(color: threshold == null ? p.muted : p.accent),
                        ),
                      ),
                      value: threshold != null,
                      onChanged: (v) => _set('auto.lowBalance', v ? '10000' : 'off'),
                    ),
                    toggle(
                      'auto.weekly',
                      a.weekly,
                      Icons.event_note_outlined,
                      'Weekly review',
                      'Sunday 19:00: the week ahead and what this week cost',
                    ),
                    toggle(
                      'auto.overdue',
                      a.overdue,
                      Icons.assignment_late_outlined,
                      'Overdue nudge',
                      '20:00 when tasks are past their date',
                    ),
                    toggle(
                      'auto.habits',
                      a.habits,
                      Icons.local_fire_department_outlined,
                      'Habit reminders',
                      'At each habit\'s time, only if not done yet',
                    ),
                    toggle(
                      'auto.backup',
                      a.backup,
                      Icons.backup_outlined,
                      'Daily backup',
                      'A copy of everything, kept for two weeks',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            ContentWidth(
              child: Section(
                title: 'Coming up',
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    children: [
                      if (_upcoming == null) const LinearProgressIndicator(minHeight: 2),
                      if (_upcoming?.isEmpty ?? false)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: Text('Nothing planned for the next week.', style: TextStyle(color: p.muted)),
                        ),
                      for (final n in (_upcoming ?? const <PlannedNote>[]).take(12))
                        ListTile(
                          dense: true,
                          title: Text(n.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(n.body, maxLines: 2, overflow: TextOverflow.ellipsis),
                          trailing: Text(
                            '${friendlyDay(n.at)}\n${n.at.hour.toString().padLeft(2, '0')}:${n.at.minute.toString().padLeft(2, '0')}',
                            textAlign: TextAlign.end,
                            style: TextStyle(color: p.muted, fontSize: 12.5),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editThreshold(int current) async {
    final c = TextEditingController(text: (current / 100).toStringAsFixed(0));
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Warn me under'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(prefixText: '${currencySymbol(context.settings.currency)} '),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    final v = parseMoney(c.text);
    if (ok == true && v != null) await _set('auto.lowBalance', '$v');
  }
}

/// Save everything to a file, restore it, or go back to a daily copy.
class BackupPage extends StatefulWidget {
  const BackupPage({super.key});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  List<File> _auto = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final dir = await backupFolder();
      if (mounted) setState(() => _auto = listBackupsSync(dir));
    } catch (_) {}
  }

  Future<void> _save() async {
    final db = context.db;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final bytes = utf8.encode(await backupJson(db));
      final where = await FilePicker.saveFile(dialogTitle: 'Save Hub backup', fileName: backupFileName(), bytes: bytes);
      messenger.showSnackBar(SnackBar(content: Text(where == null ? 'Not saved' : 'Backup saved')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not save: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await autoBackup(db);
    await _refresh();
  }

  Future<void> _restoreText(String json) async {
    final db = context.db;
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore this backup?'),
        content: const Text(
          'Everything in the backup comes back. Things you added since stay; '
          'anything that is in both is set back to the backup\'s version.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Restore')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      // Keep a copy of how things are now, in case the restore was a mistake.
      await autoBackup(db);
      final n = await restoreBackup(db, json);
      messenger.showSnackBar(SnackBar(content: Text('Restored $n items')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('That file is not a Hub backup ($e)')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pick() async {
    final files = await FilePicker.pickFiles(type: FileType.any);
    final f = files.firstOrNull;
    if (f == null) return;
    final bytes = await f.xFile.readAsBytes();
    if (!mounted) return;
    await _restoreText(utf8.decode(bytes, allowMalformed: true));
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Backup')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          ContentWidth(
            child: Text(
              'Save a backup somewhere outside the app (Google Drive, Downloads, your PC) before you reinstall '
              'or switch phones. Restoring brings every note, task, event, payment and setting back.',
              style: TextStyle(color: p.muted),
            ),
          ),
          const SizedBox(height: 14),
          ContentWidth(
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _save,
                    icon: const Icon(Icons.save_alt_rounded, size: 18),
                    label: const Text('Save backup'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _pick,
                    icon: const Icon(Icons.restore_rounded, size: 18),
                    label: const Text('Restore'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          ContentWidth(
            child: Section(
              title: 'Daily copies on this device',
              child: Column(
                children: [
                  if (_auto.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Text('The first one is made today.', style: TextStyle(color: p.muted)),
                    ),
                  for (final f in _auto)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.history_rounded),
                      title: Text(backupLabel(f)),
                      subtitle: Text('${(f.lengthSync() / 1024).toStringAsFixed(0)} KB'),
                      trailing: TextButton(
                        onPressed: _busy ? null : () async => _restoreText(await f.readAsString()),
                        child: const Text('Restore'),
                      ),
                    ),
                  const SizedBox(height: 6),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

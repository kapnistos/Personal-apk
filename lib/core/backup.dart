import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path_provider/path_provider.dart';

import 'db/database.dart';
import 'edition.dart';
import 'format.dart';

/// Tables a backup leaves out: sync bookkeeping and caches that rebuild themselves.
const _skipTables = {'sync_state', 'sync_tombstones', 'sqlite_sequence'};
const _skipSettings = {'news.cache', 'ai.openrouter.models'};

/// Everything in the database as JSON: every table, every row, including the
/// sync ids, so a restored row is the same row on every device.
Future<Map<String, dynamic>> exportBackup(AppDatabase db) async {
  final tables = await db
      .customSelect("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'")
      .get();
  final out = <String, dynamic>{};
  for (final t in tables) {
    final name = t.read<String>('name');
    if (_skipTables.contains(name)) continue;
    final rows = await db.customSelect('SELECT * FROM "$name"').get();
    out[name] = [
      for (final r in rows)
        if (name != 'settings' || !_skipSettings.contains(r.data['key'])) r.data,
    ];
  }
  return {'app': 'Hub', 'version': db.schemaVersion, 'createdAt': DateTime.now().toIso8601String(), 'tables': out};
}

Future<String> backupJson(AppDatabase db) async => jsonEncode(await exportBackup(db));

/// Puts every row from a backup back. Rows with the same id are replaced by the
/// backup's version; everything else already in the app stays. Returns the rows restored.
///
/// With [replace], the app is emptied first so it holds exactly what the backup holds.
Future<int> restoreBackup(AppDatabase db, String json, {bool replace = false}) async {
  final data = jsonDecode(json) as Map<String, dynamic>;
  if (data['app'] != 'Hub' || data['tables'] is! Map) throw const FormatException('Not a Hub backup');
  final tables = (data['tables'] as Map).cast<String, dynamic>();
  final existing = {
    for (final r in await db.customSelect("SELECT name FROM sqlite_master WHERE type = 'table'").get())
      r.read<String>('name'),
  };
  var count = 0;
  await db.transaction(() async {
    if (replace) {
      for (final name in tables.keys) {
        if (existing.contains(name) && !_skipTables.contains(name)) await db.customStatement('DELETE FROM "$name"');
      }
    }
    for (final entry in tables.entries) {
      if (!existing.contains(entry.key) || _skipTables.contains(entry.key)) continue;
      final columns = {
        for (final c in await db.customSelect('PRAGMA table_info("${entry.key}")').get()) c.read<String>('name'),
      };
      for (final raw in entry.value as List) {
        final row = (raw as Map).cast<String, dynamic>()..removeWhere((k, _) => !columns.contains(k));
        if (row.isEmpty) continue;
        final keys = row.keys.toList();
        await db.customStatement(
          'INSERT OR REPLACE INTO "${entry.key}" (${keys.map((k) => '"$k"').join(', ')}) '
          'VALUES (${List.filled(keys.length, '?').join(', ')})',
          [for (final k in keys) row[k]],
        );
        count++;
      }
    }
    // Emptying the tables marked every row as deleted for sync; the ones that came straight back are not.
    if (replace && existing.contains('sync_tombstones')) {
      for (final name in tables.keys) {
        if (!existing.contains(name) || _skipTables.contains(name)) continue;
        final hasGid = (await db.customSelect('PRAGMA table_info("$name")').get()).any(
          (c) => c.read<String>('name') == 'gid',
        );
        if (hasGid) await db.customStatement('DELETE FROM sync_tombstones WHERE gid IN (SELECT gid FROM "$name")');
      }
    }
  });
  // Drift's streams don't see raw SQL writes; tell them everything changed.
  db.notifyUpdates({for (final t in db.allTables) TableUpdate.onTable(t)});
  await checkImportedApps(db);
  return count;
}

/// Where automatic backups go: inside the app's own folder, one file a day, the last two weeks kept.
Future<Directory> backupFolder() async {
  final base = await getApplicationSupportDirectory();
  final dir = Directory('${base.path}${Platform.pathSeparator}backups');
  if (!await dir.exists()) await dir.create(recursive: true);
  return dir;
}

/// Writes today's backup if there isn't one yet. Safe to call on every start.
Future<File?> autoBackup(AppDatabase db, {int keep = 14}) async {
  try {
    final dir = await backupFolder();
    final today = AppDatabase.dayKey(DateTime.now());
    final file = File('${dir.path}${Platform.pathSeparator}hub-$today.json');
    if (!await file.exists()) {
      // Written beside it first, so a crash mid-write never leaves a broken file that counts as today's backup.
      final part = File('${file.path}.part');
      await part.writeAsString(await backupJson(db), flush: true);
      await part.rename(file.path);
    }
    final all = await dir.list().where((f) => f is File && f.path.endsWith('.json')).cast<File>().toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    for (final old in all.skip(keep)) {
      await old.delete();
    }
    return file;
  } catch (_) {
    return null;
  }
}

/// Backups in [dir], newest first.
List<File> listBackupsSync(Directory dir) =>
    dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList()
      ..sort((a, b) => b.path.compareTo(a.path));

String backupFileName([DateTime? at]) => 'hub-backup-${AppDatabase.dayKey(at ?? DateTime.now())}.json';

/// "30 Oct" from a backup file name.
String backupLabel(File f) {
  final m = RegExp(r'(\d{4})-(\d{2})-(\d{2})').firstMatch(f.path);
  if (m == null) return f.uri.pathSegments.last;
  return friendlyDay(DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!)));
}

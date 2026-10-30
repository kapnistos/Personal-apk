import 'package:drift/drift.dart';

import '../db/database.dart';
import 'sync_schema.dart';

/// Reads local changes and applies remote ones. Shared by the server and the client.
class SyncEngine {
  SyncEngine(this.db);
  final AppDatabase db;

  static int now() => DateTime.now().millisecondsSinceEpoch;

  Future<void> setRole(String role) =>
      db.customStatement('UPDATE sync_state SET role = ? WHERE id = 1', [role]);

  Future<Map<String, int>> state() async {
    final r = await db.customSelect('SELECT last_pull, last_push FROM sync_state WHERE id = 1').getSingle();
    return {'lastPull': r.read<int>('last_pull'), 'lastPush': r.read<int>('last_push')};
  }

  Future<void> saveState({int? lastPull, int? lastPush}) async {
    if (lastPull != null) await db.customStatement('UPDATE sync_state SET last_pull = ? WHERE id = 1', [lastPull]);
    if (lastPush != null) await db.customStatement('UPDATE sync_state SET last_push = ? WHERE id = 1', [lastPush]);
  }

  Future<List<String>> _columns(String table) async {
    final rows = await db.customSelect('PRAGMA table_info($table)').get();
    return rows.map((r) => r.read<String>('name')).toList();
  }

  /// Everything this database changed after [since] (its own clock).
  Future<Map<String, dynamic>> collect(int since) async {
    final tables = <String, List<Map<String, Object?>>>{};
    for (final t in syncedTables) {
      final where = ['srv > ?', 'gid IS NOT NULL', if (syncLocalOnly[t] != null) 'NOT (${syncLocalOnly[t]})'].join(' AND ');
      final rows = await db.customSelect('SELECT * FROM $t WHERE $where', variables: [Variable.withInt(since)]).get();
      if (rows.isEmpty) continue;
      final fks = syncForeignKeys[t] ?? const {};
      final out = <Map<String, Object?>>[];
      for (final r in rows) {
        final m = Map<String, Object?>.of(r.data)..remove('id')..remove('srv');
        for (final MapEntry(key: col, value: parent) in fks.entries) {
          final localId = m.remove(col);
          m['${col}_gid'] = localId == null ? null : await _gidOf(parent, localId as int);
        }
        out.add(m);
      }
      tables[t] = out;
    }
    final tombs = await db
        .customSelect('SELECT gid, tbl, at FROM sync_tombstones WHERE srv > ?', variables: [Variable.withInt(since)])
        .get();
    return {
      'rows': tables,
      'tombstones': [for (final r in tombs) {'gid': r.read<String>('gid'), 'tbl': r.read<String>('tbl'), 'at': r.read<int>('at')}],
    };
  }

  Future<String?> _gidOf(String table, int id) async {
    final r = await db.customSelect('SELECT gid FROM $table WHERE id = ?', variables: [Variable.withInt(id)]).getSingleOrNull();
    return r?.read<String?>('gid');
  }

  Future<int?> _idOf(String table, String gid) async {
    final r = await db.customSelect('SELECT id FROM $table WHERE gid = ?', variables: [Variable.withString(gid)]).getSingleOrNull();
    return r?.read<int>('id');
  }

  /// Applies changes from another device, last writer wins. Returns rows changed.
  Future<int> apply(Map<String, dynamic> payload) async {
    var changed = 0;
    final touched = <String>{};
    await db.transaction(() async {
      await db.customStatement('UPDATE sync_state SET applying = 1 WHERE id = 1');
      try {
        final rows = (payload['rows'] as Map?)?.cast<String, dynamic>() ?? const {};
        for (final t in syncedTables) {
          final list = (rows[t] as List?) ?? const [];
          if (list.isEmpty) continue;
          final cols = (await _columns(t)).toSet()..remove('id')..remove('srv');
          final fks = syncForeignKeys[t] ?? const {};
          for (final raw in list) {
            final m = Map<String, Object?>.of((raw as Map).cast<String, Object?>());
            final gid = m['gid'] as String?;
            final modified = (m['modified'] as num?)?.toInt() ?? 0;
            if (gid == null) continue;
            final tomb = await db
                .customSelect('SELECT at FROM sync_tombstones WHERE gid = ?', variables: [Variable.withString(gid)])
                .getSingleOrNull();
            if (tomb != null && tomb.read<int>('at') >= modified) continue;
            final local = await db
                .customSelect('SELECT modified FROM $t WHERE gid = ?', variables: [Variable.withString(gid)])
                .getSingleOrNull();
            if (local != null && local.read<int>('modified') >= modified) continue;
            for (final MapEntry(key: col, value: parent) in fks.entries) {
              // A device on an older version may not send this link at all; keep ours then.
              if (!m.containsKey('${col}_gid')) continue;
              final parentGid = m.remove('${col}_gid') as String?;
              m[col] = parentGid == null ? null : await _idOf(parent, parentGid);
            }
            // A child whose required parent is unknown here is skipped until the parent arrives.
            final required = syncRequiredKeys[t];
            if (required != null && m[required] == null) continue;
            final keys = m.keys.where(cols.contains).toList();
            final values = [for (final k in keys) _variable(m[k])];
            if (local != null) {
              await db.customUpdate(
                'UPDATE $t SET ${keys.map((k) => '$k = ?').join(', ')} WHERE gid = ?',
                variables: [...values, Variable.withString(gid)],
              );
            } else {
              await db.customInsert(
                'INSERT OR IGNORE INTO $t (${keys.join(', ')}) VALUES (${keys.map((_) => '?').join(', ')})',
                variables: values,
              );
            }
            if (tomb != null) {
              await db.customStatement('DELETE FROM sync_tombstones WHERE gid = ?', [gid]);
            }
            changed++;
            touched.add(t);
          }
        }
        for (final raw in (payload['tombstones'] as List?) ?? const []) {
          final m = (raw as Map).cast<String, Object?>();
          final gid = m['gid'] as String, t = m['tbl'] as String, at = (m['at'] as num).toInt();
          if (!syncedTables.contains(t)) continue;
          final local = await db
              .customSelect('SELECT modified FROM $t WHERE gid = ?', variables: [Variable.withString(gid)])
              .getSingleOrNull();
          if (local != null && local.read<int>('modified') > at) continue;
          if (local != null) {
            await db.customUpdate('DELETE FROM $t WHERE gid = ?', variables: [Variable.withString(gid)]);
            changed++;
            touched.add(t);
          }
          await db.customStatement(
            'INSERT OR REPLACE INTO sync_tombstones (gid, tbl, at, srv) VALUES (?, ?, ?, '
            "CASE WHEN (SELECT role FROM sync_state WHERE id = 1) = 'client' THEN 0 ELSE ? END)",
            [gid, t, at, now()],
          );
        }
      } finally {
        await db.customStatement('UPDATE sync_state SET applying = 0 WHERE id = 1');
      }
    });
    if (touched.isNotEmpty) {
      db.notifyUpdates({for (final t in touched) TableUpdate(t)});
    }
    return changed;
  }

  static Variable _variable(Object? v) => switch (v) {
        null => const Variable(null),
        final int i => Variable.withInt(i),
        final double d => Variable.withReal(d),
        final bool b => Variable.withBool(b),
        final String s => Variable.withString(s),
        _ => Variable(v.toString()),
      };
}

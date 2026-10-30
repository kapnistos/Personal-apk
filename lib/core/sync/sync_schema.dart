/// Sync bookkeeping that lives beside the app's tables, in plain SQL, so the
/// rest of the app reads and writes its tables without knowing about sync.
///
/// Every synced table gets three hidden columns:
///   gid       global id shared by all devices
///   modified  when the row was last edited by a person (ms), for last-writer-wins
///   srv       when this database last changed the row (ms), to find what to send
/// Triggers fill them in, and deletions leave a tombstone.
library;

/// Synced tables in dependency order (parents before children).
const syncedTables = [
  'cities',
  'notes',
  'calendars',
  'spaces',
  'todos',
  'events',
  'subscriptions',
  'entries',
  'budgets',
  'space_items',
  'savings_goals',
  'savings_moves',
  'holdings',
  'work_days',
  'applications',
  'accounts',
  'shopping_items',
];

/// Tables keyed by a natural key instead of an id; the key doubles as the gid.
const syncNaturalKeys = {'budgets': 'category', 'work_days': 'day'};

/// Foreign keys that must travel as gids: table -> {column: parent table}.
const syncForeignKeys = {
  'events': {'calendar_id': 'calendars'},
  'entries': {'subscription_id': 'subscriptions'},
  'spaces': {'calendar_id': 'calendars'},
  'todos': {'space_id': 'spaces'},
  'space_items': {'space_id': 'spaces'},
  'savings_moves': {'goal_id': 'savings_goals'},
};

/// Foreign keys a row cannot live without; such rows wait until the parent has arrived.
const syncRequiredKeys = {'events': 'calendar_id', 'space_items': 'space_id', 'savings_moves': 'goal_id'};

/// Rows that stay on one device: feed calendars and their events are re-downloaded per device.
const syncLocalOnly = {'events': 'uid IS NOT NULL'};

const _nowMs = "CAST((julianday('now') - 2440587.5) * 86400000 AS INTEGER)";
const _newGid = 'lower(hex(randomblob(16)))';

/// 1 while incoming changes are being applied.
const _applying = '(SELECT applying FROM sync_state WHERE id = 1)';

/// On a client, rows written by sync are not "changed here" and need not go back.
const _srvValue =
    "CASE WHEN $_applying = 1 AND (SELECT role FROM sync_state WHERE id = 1) = 'client' "
    'THEN 0 ELSE $_nowMs END';

/// Statements that add sync to [only] (default: every synced table).
List<String> syncInstallStatements({List<String>? only}) {
  final s = <String>[
    'CREATE TABLE IF NOT EXISTS sync_state ('
        'id INTEGER PRIMARY KEY CHECK (id = 1), '
        "role TEXT NOT NULL DEFAULT 'none', "
        'applying INTEGER NOT NULL DEFAULT 0, '
        'last_pull INTEGER NOT NULL DEFAULT 0, '
        'last_push INTEGER NOT NULL DEFAULT 0)',
    'INSERT OR IGNORE INTO sync_state (id) VALUES (1)',
    'CREATE TABLE IF NOT EXISTS sync_tombstones ('
        'gid TEXT PRIMARY KEY, tbl TEXT NOT NULL, at INTEGER NOT NULL, srv INTEGER NOT NULL)',
  ];
  for (final t in only ?? syncedTables) {
    final natural = syncNaturalKeys[t];
    final gidExpr = natural != null ? 'NEW.$natural' : 'coalesce(NEW.gid, $_newGid)';
    final localOnly = syncLocalOnly[t];
    final deleteWhen =
        'WHEN $_applying = 0 AND OLD.gid IS NOT NULL${localOnly == null ? '' : ' AND NOT (${localOnly.replaceAll('uid', 'OLD.uid')})'}';
    s.addAll([
      'ALTER TABLE $t ADD COLUMN gid TEXT',
      'ALTER TABLE $t ADD COLUMN modified INTEGER NOT NULL DEFAULT 0',
      'ALTER TABLE $t ADD COLUMN srv INTEGER NOT NULL DEFAULT 0',
      'UPDATE $t SET gid = ${natural ?? _newGid}, modified = $_nowMs, srv = $_nowMs',
      'CREATE UNIQUE INDEX IF NOT EXISTS ${t}_gid ON $t (gid)',
      'CREATE TRIGGER IF NOT EXISTS ${t}_sync_ins AFTER INSERT ON $t BEGIN '
          'UPDATE $t SET gid = $gidExpr, '
          'modified = CASE WHEN $_applying = 1 THEN NEW.modified ELSE $_nowMs END, '
          'srv = $_srvValue WHERE rowid = NEW.rowid; END',
      'CREATE TRIGGER IF NOT EXISTS ${t}_sync_upd AFTER UPDATE ON $t BEGIN '
          'UPDATE $t SET gid = $gidExpr, '
          'modified = CASE WHEN $_applying = 1 THEN NEW.modified ELSE $_nowMs END, '
          'srv = $_srvValue WHERE rowid = NEW.rowid; END',
      'CREATE TRIGGER IF NOT EXISTS ${t}_sync_del AFTER DELETE ON $t $deleteWhen BEGIN '
          "INSERT OR REPLACE INTO sync_tombstones (gid, tbl, at, srv) VALUES (OLD.gid, '$t', $_nowMs, $_nowMs); END",
    ]);
  }
  return s;
}

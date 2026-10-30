import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../format.dart';
import '../sync/sync_schema.dart';
import '../edition.dart';
import 'my_recurring.dart';

export 'my_recurring.dart';

part 'database.g.dart';

class Notes extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get body => text().withDefault(const Constant(''))();
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  /// Card colour as an index into noteColors; 0 is plain.
  IntColumn get color => integer().withDefault(const Constant(0))();
}

class Todos extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text()();
  TextColumn get details => text().withDefault(const Constant(''))();
  DateTimeColumn get due => dateTime().nullable()();
  BoolColumn get done => boolean().withDefault(const Constant(false))();
  BoolColumn get important => boolean().withDefault(const Constant(false))();
  DateTimeColumn get remindAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get completedAt => dateTime().nullable()();

  /// none, daily, weekdays, weekly, monthly, yearly. Completing a repeating task adds the next one.
  TextColumn get repeat => text().withDefault(const Constant('none'))();

  /// The space (Job, Lab research, University) this task belongs to, if any.
  IntColumn get spaceId => integer().nullable()();
}

/// A part of life with its own schedule and saved things: Job, Lab research, University.
class Spaces extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();

  /// Key into spaceIcons.
  TextColumn get icon => text().withDefault(const Constant('folder'))();
  IntColumn get color => integer()();

  /// The calendar that holds this space's schedule.
  IntColumn get calendarId => integer().nullable()();
  IntColumn get position => integer().withDefault(const Constant(0))();
}

/// A daily habit to keep, like reading or the gym.
class Habits extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();

  /// Key into habitIcons.
  TextColumn get icon => text().withDefault(const Constant('check'))();
  IntColumn get color => integer()();

  /// Days it applies to, Monday first: "1111100" is weekdays.
  TextColumn get days => text().withDefault(const Constant('1111111'))();

  /// Reminder time "HH:MM", or empty for none.
  TextColumn get remindAt => text().withDefault(const Constant(''))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  IntColumn get position => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// A day a habit was done.
class HabitChecks extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get habitId => integer()();

  /// yyyy-mm-dd
  TextColumn get day => text()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {habitId, day},
  ];
}

/// Something to buy, and the shop it is cheapest at.
class ShoppingItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get quantity => text().withDefault(const Constant(''))();

  /// Where to buy it; empty until sorted.
  TextColumn get store => text().withDefault(const Constant(''))();
  TextColumn get category => text().withDefault(const Constant(''))();
  BoolColumn get done => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// A bank account or card whose balance Hub keeps track of.
class Accounts extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Matches the account name on entries and recurring payments.
  TextColumn get name => text()();
  IntColumn get color => integer()();

  /// The balance as it stood on [balanceAt]; later entries move it.
  IntColumn get balanceCents => integer().withDefault(const Constant(0))();
  DateTimeColumn get balanceAt => dateTime().nullable()();
  TextColumn get number => text().withDefault(const Constant(''))();
  IntColumn get position => integer().withDefault(const Constant(0))();
}

/// Something worth keeping in a space: a note, a link or a file on this device.
class SpaceItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get spaceId => integer()();

  /// note, link or file
  TextColumn get kind => text()();
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get body => text().withDefault(const Constant(''))();
  TextColumn get url => text().withDefault(const Constant(''))();
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// One day in the work log: worked, off, holiday, sick or remote.
class WorkDays extends Table {
  /// yyyy-mm-dd
  TextColumn get day => text()();
  TextColumn get status => text()();
  RealColumn get hours => real().nullable()();
  TextColumn get note => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {day};
}

/// An internship (or job) to apply for, and how far it got.
class Applications extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get company => text()();
  TextColumn get role => text().withDefault(const Constant(''))();
  TextColumn get location => text().withDefault(const Constant(''))();
  TextColumn get url => text().withDefault(const Constant(''))();

  /// wishlist, preparing, applied, interview, offer, rejected
  TextColumn get status => text().withDefault(const Constant('wishlist'))();
  DateTimeColumn get deadline => dateTime().nullable()();
  DateTimeColumn get remindAt => dateTime().nullable()();
  DateTimeColumn get appliedAt => dateTime().nullable()();
  TextColumn get notes => text().withDefault(const Constant(''))();
  BoolColumn get favourite => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

class SavingsGoals extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  IntColumn get targetCents => integer()();
  DateTimeColumn get deadline => dateTime().nullable()();
  IntColumn get color => integer()();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Money put into (positive) or taken out of (negative) a savings goal.
class SavingsMoves extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get goalId => integer()();
  IntColumn get amountCents => integer()();
  DateTimeColumn get date => dateTime()();
  TextColumn get note => text().withDefault(const Constant(''))();
}

/// One investment position. Prices are per unit in the app currency.
class Holdings extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();

  /// Ticker as Yahoo Finance knows it (VWRL.AS, AAPL, BTC-EUR), or empty.
  TextColumn get symbol => text().withDefault(const Constant(''))();

  /// stock, etf, fund, crypto, bond, other
  TextColumn get kind => text().withDefault(const Constant('etf'))();
  RealColumn get units => real()();
  IntColumn get investedCents => integer()();
  RealColumn get price => real()();
  DateTimeColumn get priceAt => dateTime().nullable()();
  TextColumn get account => text().withDefault(const Constant(''))();
}

class Cities extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get region => text().withDefault(const Constant(''))();
  RealColumn get latitude => real()();
  RealColumn get longitude => real()();
  IntColumn get position => integer().withDefault(const Constant(0))();
}

/// What a wallet entry is. Stored by name.
enum EntryKind { expense, income, subscription, tax, transfer }

/// Money is stored in cents so sums never drift. Amounts are always positive;
/// the kind decides whether money comes in or goes out.
class Entries extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get amountCents => integer()();
  TextColumn get kind => textEnum<EntryKind>()();
  TextColumn get category => text()();
  TextColumn get note => text().withDefault(const Constant(''))();
  TextColumn get account => text().withDefault(const Constant(''))();
  DateTimeColumn get date => dateTime()();
  IntColumn get subscriptionId => integer().nullable()();
  TextColumn get importKey => text().nullable().unique()();
}

/// Recurring payments (Netflix, rent, insurance) and recurring income.
class Subscriptions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  IntColumn get amountCents => integer()();
  TextColumn get kind => textEnum<EntryKind>()();
  TextColumn get category => text()();
  TextColumn get account => text().withDefault(const Constant(''))();

  /// Billing period in months: 1 monthly, 3 quarterly, 12 yearly.
  IntColumn get periodMonths => integer().withDefault(const Constant(1))();
  DateTimeColumn get nextDate => dateTime()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
}

class Calendars extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  IntColumn get color => integer()();
  BoolColumn get visible => boolean().withDefault(const Constant(true))();

  /// Set for read-only calendars subscribed from an .ics link.
  TextColumn get icsUrl => text().nullable()();
  DateTimeColumn get syncedAt => dateTime().nullable()();
}

class Events extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get calendarId => integer().references(Calendars, #id)();
  TextColumn get title => text()();
  TextColumn get location => text().withDefault(const Constant(''))();
  TextColumn get notes => text().withDefault(const Constant(''))();
  DateTimeColumn get start => dateTime()();
  DateTimeColumn get end => dateTime()();
  BoolColumn get allDay => boolean().withDefault(const Constant(false))();

  /// none, daily, weekly, monthly, yearly
  TextColumn get repeat => text().withDefault(const Constant('none'))();

  /// Minutes before start; null means no reminder.
  IntColumn get remindMinutes => integer().nullable()();

  /// UID from the feed for subscribed events.
  TextColumn get uid => text().nullable()();
}

class Budgets extends Table {
  TextColumn get category => text()();
  IntColumn get monthlyCents => integer()();

  @override
  Set<Column> get primaryKey => {category};
}

/// A mail account. The password lives in the OS keystore, not here.
class MailboxAccounts extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// gmail, proton, outlook or imap
  TextColumn get provider => text()();
  TextColumn get name => text()();
  TextColumn get email => text()();
  TextColumn get imapHost => text()();
  IntColumn get imapPort => integer()();

  /// ssl or starttls
  TextColumn get imapSecurity => text()();
  TextColumn get smtpHost => text()();
  IntColumn get smtpPort => integer()();
  TextColumn get smtpSecurity => text()();
  IntColumn get color => integer()();

  /// Proton Bridge uses a self-signed certificate on the local machine.
  BoolColumn get allowSelfSigned => boolean().withDefault(const Constant(false))();
}

class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(
  tables: [
    Notes,
    Todos,
    Cities,
    Entries,
    Subscriptions,
    Budgets,
    Calendars,
    Events,
    MailboxAccounts,
    Settings,
    Spaces,
    SpaceItems,
    SavingsGoals,
    SavingsMoves,
    Holdings,
    WorkDays,
    Applications,
    Accounts,
    ShoppingItems,
    Habits,
    HabitChecks,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? driftDatabase(name: 'hub'));

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await into(cities).insert(
        CitiesCompanion.insert(
          name: 'Amsterdam',
          region: const Value('North Holland, Netherlands'),
          latitude: 52.37403,
          longitude: 4.88969,
        ),
      );
      await batch(
        (b) => b.insertAll(calendars, [
          CalendarsCompanion.insert(name: 'Personal', color: 0xFF3A78C9),
          CalendarsCompanion.insert(name: 'Work', color: 0xFF1F7A5A),
          CalendarsCompanion.insert(name: 'Study', color: 0xFFC0563F),
        ]),
      );
      await _seedSpaces();
      await _seedAccounts();
      await restoreRecurring();
      await restoreTasks();
      await _installSync();
      await _fixSpaceGids();
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) await m.createTable(mailboxAccounts);
      if (from < 3) {
        await m.addColumn(calendars, calendars.icsUrl);
        await m.addColumn(calendars, calendars.syncedAt);
        await m.addColumn(events, events.uid);
      }
      if (from < 4) await _installSync(only: syncedTables.where((t) => !spaceTables.contains(t)).toList());
      if (from < 5) {
        await m.addColumn(todos, todos.repeat);
        await m.addColumn(todos, todos.spaceId);
        await m.addColumn(notes, notes.color);
        for (final TableInfo t in [
          spaces,
          spaceItems,
          savingsGoals,
          savingsMoves,
          holdings,
          workDays,
          applications,
          accounts,
          shoppingItems,
        ]) {
          await m.createTable(t);
        }
        await _seedSpaces();
        await _seedAccounts();
        await restoreRecurring();
        for (final sql in syncInstallStatements(only: spaceTables)) {
          await customStatement(sql);
        }
        await _fixSpaceGids();
      }
      if (from < 6) {
        await m.createTable(habits);
        await m.createTable(habitChecks);
        for (final sql in syncInstallStatements(only: habitTables)) {
          await customStatement(sql);
        }
      }
    },
    beforeOpen: (details) async {
      // Sync triggers assume this stays off (it is SQLite's default).
      await customStatement('PRAGMA recursive_triggers = OFF');
    },
  );

  /// Tables added in version 6 that sync.
  static const habitTables = ['habits', 'habit_checks'];

  /// Tables added in version 5 that sync.
  static const spaceTables = [
    'spaces',
    'space_items',
    'savings_goals',
    'savings_moves',
    'holdings',
    'work_days',
    'applications',
    'accounts',
    'shopping_items',
  ];

  /// Job, Lab research and University, each tied to its own calendar.
  Future<void> _seedSpaces() async {
    Future<int> calendarNamed(String name, int color) async {
      final existing = await (select(
        calendars,
      )..where((c) => c.name.equals(name) & c.icsUrl.isNull())).getSingleOrNull();
      return existing?.id ?? into(calendars).insert(CalendarsCompanion.insert(name: name, color: color));
    }

    final work = await calendarNamed('Work', 0xFF1F7A5A);
    // The public build has no Lab.
    final lab = personalEdition ? await calendarNamed('Lab', 0xFF7A5BC0) : null;
    final study = await calendarNamed('Study', 0xFFC0563F);
    await batch(
      (b) => b.insertAll(spaces, [
        SpacesCompanion.insert(
          name: 'Job',
          icon: const Value('work'),
          color: 0xFF1F7A5A,
          calendarId: Value(work),
          position: const Value(0),
        ),
        if (lab != null)
        SpacesCompanion.insert(
          name: 'Lab research',
          icon: const Value('science'),
          color: 0xFF7A5BC0,
          calendarId: Value(lab),
          position: const Value(1),
        ),
        SpacesCompanion.insert(
          name: 'University',
          icon: const Value('school'),
          color: 0xFFC0563F,
          calendarId: Value(study),
          position: const Value(2),
        ),
      ]),
    );
  }

  /// The three cards: ABN AMRO, Revolut and Eurobank.
  Future<void> _seedAccounts() async {
    if ((await select(accounts).get()).isNotEmpty) return;
    await batch(
      (b) => b.insertAll(accounts, [
        AccountsCompanion.insert(name: 'ABN AMRO', color: 0xFF00716B, position: const Value(0)),
        AccountsCompanion.insert(name: 'Revolut', color: 0xFF2F55D4, position: const Value(1)),
        AccountsCompanion.insert(name: 'Eurobank', color: 0xFFB3122E, position: const Value(2)),
      ]),
    );
  }

  /// The owner's usual monthly payments and income (my_recurring.dart). Adds the ones missing (by name)
  /// and leaves any that are already there alone. Returns how many it added.
  Future<int> restoreRecurring({DateTime? now}) async {
    final today = dateOnly(now ?? DateTime.now());
    final have = {for (final s in await select(subscriptions).get()) s.name.trim().toLowerCase()};
    var added = 0;
    for (final r in myRecurring) {
      if (have.contains(r.name.toLowerCase())) continue;
      // Move the first date on to the next one still ahead.
      var next = r.next;
      while (next.isBefore(today)) {
        next = addMonths(next, 1);
      }
      await into(subscriptions).insert(
        SubscriptionsCompanion.insert(
          name: r.name,
          amountCents: r.cents,
          kind: r.kind,
          category: r.category,
          nextDate: next,
        ),
      );
      added++;
    }
    return added;
  }

  /// The owner's open tasks (my_recurring.dart). Adds the ones missing (by title). Returns how many it added.
  Future<int> restoreTasks() async {
    final have = {for (final t in await select(todos).get()) t.title.trim().toLowerCase()};
    var added = 0;
    for (final title in myTasks) {
      if (have.contains(title.toLowerCase())) continue;
      await into(todos).insert(TodosCompanion.insert(title: title));
      added++;
    }
    return added;
  }

  /// Starter spaces and the Lab calendar get fixed ids so devices merge them.
  Future<void> _fixSpaceGids() async {
    for (final (name, gid) in [('Job', 'seed-job'), ('Lab research', 'seed-lab'), ('University', 'seed-uni')]) {
      await customStatement('UPDATE spaces SET gid = ?, modified = 1 WHERE name = ? AND id <= 3', [gid, name]);
    }
    for (final (name, gid) in [('ABN AMRO', 'seed-abn'), ('Revolut', 'seed-revolut'), ('Eurobank', 'seed-eurobank')]) {
      await customStatement('UPDATE accounts SET gid = ?, modified = 1 WHERE name = ? AND id <= 3', [gid, name]);
    }
    await customStatement(
      "UPDATE calendars SET gid = 'seed-lab-cal', modified = 1 WHERE name = 'Lab' AND ics_url IS NULL "
      "AND id = (SELECT min(id) FROM calendars WHERE name = 'Lab' AND ics_url IS NULL)",
    );
  }

  Future<void> _installSync({List<String>? only}) async {
    for (final sql in syncInstallStatements(only: only)) {
      await customStatement(sql);
    }
    // The rows every install starts with get fixed ids, so two devices merge
    // them instead of each showing the other's copy.
    await customStatement("UPDATE cities SET gid = 'seed-amsterdam' WHERE id = 1 AND name = 'Amsterdam'");
    for (final (id, name) in [(1, 'Personal'), (2, 'Work'), (3, 'Study')]) {
      await customStatement(
        "UPDATE calendars SET gid = 'seed-${name.toLowerCase()}', modified = 1 WHERE id = ? AND name = ?",
        [id, name],
      );
    }
    await customStatement("UPDATE cities SET modified = 1 WHERE gid = 'seed-amsterdam'");
  }

  // Notes

  Stream<List<Note>> watchNotes({String query = ''}) {
    final q = select(notes)..orderBy([(n) => OrderingTerm.desc(n.pinned), (n) => OrderingTerm.desc(n.updatedAt)]);
    final trimmed = query.trim();
    if (trimmed.isNotEmpty) {
      final pattern = '%$trimmed%';
      q.where((n) => n.title.like(pattern) | n.body.like(pattern));
    }
    return q.watch();
  }

  Future<void> setNoteColor(int id, int color) =>
      (update(notes)..where((n) => n.id.equals(id))).write(NotesCompanion(color: Value(color)));

  Future<int> saveNote({int? id, required String title, required String body}) {
    final now = DateTime.now();
    if (id == null) {
      return into(notes).insert(
        NotesCompanion.insert(title: Value(title), body: Value(body), createdAt: Value(now), updatedAt: Value(now)),
      );
    }
    return (update(notes)..where((n) => n.id.equals(id)))
        .write(NotesCompanion(title: Value(title), body: Value(body), updatedAt: Value(now)))
        .then((_) => id);
  }

  Future<void> setNotePinned(int id, bool pinned) =>
      (update(notes)..where((n) => n.id.equals(id))).write(NotesCompanion(pinned: Value(pinned)));

  Future<void> deleteNote(int id) => (delete(notes)..where((n) => n.id.equals(id))).go();

  Future<void> restoreNote(Note note) => into(notes).insert(note, mode: InsertMode.insertOrReplace);

  // To-do

  Stream<List<Todo>> watchTodos() =>
      (select(todos)..orderBy([
            (t) => OrderingTerm.asc(t.done),
            (t) => OrderingTerm(expression: t.due, nulls: NullsOrder.last),
            (t) => OrderingTerm.desc(t.important),
            (t) => OrderingTerm.desc(t.createdAt),
          ]))
          .watch();

  Future<int> addTodo(
    String title, {
    DateTime? due,
    DateTime? remindAt,
    bool important = false,
    String repeat = 'none',
    int? spaceId,
  }) => into(todos).insert(
    TodosCompanion.insert(
      title: title,
      due: Value(due),
      remindAt: Value(remindAt),
      important: Value(important),
      repeat: Value(repeat),
      spaceId: Value(spaceId),
    ),
  );

  Future<Todo?> todoById(int id) => (select(todos)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Moves a reminder later, for "Snooze" on a notification.
  Future<void> snoozeTodo(int id, Duration by) =>
      (update(todos)..where((t) => t.id.equals(id))).write(TodosCompanion(remindAt: Value(DateTime.now().add(by))));

  Future<void> updateTodo(Todo todo) => update(todos).replace(todo);

  /// Ticks a task off. A repeating task gets its next copy, moved on by one period.
  Future<void> setTodoDone(int id, bool done) => transaction(() async {
    final t = await todoById(id);
    if (t == null) return;
    await (update(todos)..where((t) => t.id.equals(id))).write(
      TodosCompanion(done: Value(done), completedAt: Value(done ? DateTime.now() : null)),
    );
    if (!done || t.done || t.repeat == 'none') return;
    final base = t.due ?? t.remindAt ?? dateOnly(DateTime.now());
    var next = nextRepeat(base, t.repeat);
    // Catch up if the task was finished late, so the next one is not already overdue.
    final today = dateOnly(DateTime.now());
    while (dateOnly(next).isBefore(today)) {
      next = nextRepeat(next, t.repeat);
    }
    final shift = next.difference(base);
    await into(todos).insert(
      TodosCompanion.insert(
        title: t.title,
        details: Value(t.details),
        important: Value(t.important),
        repeat: Value(t.repeat),
        spaceId: Value(t.spaceId),
        due: Value(t.due == null ? null : next),
        remindAt: Value(t.remindAt?.add(shift)),
      ),
    );
  });

  Future<void> deleteTodo(int id) => (delete(todos)..where((t) => t.id.equals(id))).go();

  Future<void> restoreTodo(Todo todo) => into(todos).insert(todo, mode: InsertMode.insertOrReplace);

  Future<int> clearCompletedTodos() => (delete(todos)..where((t) => t.done.equals(true))).go();

  // Weather cities

  Stream<List<City>> watchCities() =>
      (select(cities)..orderBy([(c) => OrderingTerm.asc(c.position), (c) => OrderingTerm.asc(c.id)])).watch();

  Future<void> addCity(String name, String region, double lat, double lon) async {
    final count = await cities.count().getSingle();
    await into(cities).insert(
      CitiesCompanion.insert(name: name, region: Value(region), latitude: lat, longitude: lon, position: Value(count)),
    );
  }

  Future<void> updateCity(City c) => update(cities).replace(c);

  Future<void> deleteCity(int id) => (delete(cities)..where((c) => c.id.equals(id))).go();

  Future<void> reorderCities(List<City> ordered) => batch((b) {
    for (var i = 0; i < ordered.length; i++) {
      b.update(cities, CitiesCompanion(position: Value(i)), where: (c) => c.id.equals(ordered[i].id));
    }
  });

  // Finance

  Stream<List<Entry>> watchEntries(DateTime from, DateTime to) =>
      (select(entries)
            ..where((e) => e.date.isBiggerOrEqualValue(from) & e.date.isSmallerThanValue(to))
            ..orderBy([(e) => OrderingTerm.desc(e.date), (e) => OrderingTerm.desc(e.id)]))
          .watch();

  Future<int> addEntry(EntriesCompanion entry) => into(entries).insert(entry);

  Future<void> updateEntry(Entry entry) => update(entries).replace(entry);

  Future<void> deleteEntry(int id) => (delete(entries)..where((e) => e.id.equals(id))).go();

  Future<void> restoreEntry(Entry entry) => into(entries).insert(entry, mode: InsertMode.insertOrReplace);

  Future<void> insertEntries(List<EntriesCompanion> rows) => batch((b) => b.insertAll(entries, rows));

  Stream<List<Budget>> watchBudgets() => select(budgets).watch();

  Future<void> setBudget(String category, int? monthlyCents) {
    if (monthlyCents == null || monthlyCents <= 0) {
      return (delete(budgets)..where((b) => b.category.equals(category))).go();
    }
    return into(budgets)
        .insertOnConflictUpdate(BudgetsCompanion.insert(category: category, monthlyCents: monthlyCents));
  }

  Stream<List<Subscription>> watchSubscriptions() => (select(
    subscriptions,
  )..orderBy([(s) => OrderingTerm.desc(s.active), (s) => OrderingTerm.asc(s.nextDate)])).watch();

  Future<int> saveSubscription(SubscriptionsCompanion s) => into(subscriptions).insertOnConflictUpdate(s);

  Future<void> deleteSubscription(int id) => (delete(subscriptions)..where((s) => s.id.equals(id))).go();

  /// Books every subscription payment that has come due, then moves its next
  /// date forward. Safe to call on every app start.
  Future<int> bookDueSubscriptions({DateTime? now}) async {
    final today = now ?? DateTime.now();
    var booked = 0;
    await transaction(() async {
      final due = await (select(
        subscriptions,
      )..where((s) => s.active.equals(true) & s.nextDate.isSmallerOrEqualValue(today))).get();
      for (final s in due) {
        // Keyed by the subscription's global id so two synced devices book a payment once.
        final gidRow = await customSelect(
          'SELECT gid FROM subscriptions WHERE id = ?',
          variables: [Variable.withInt(s.id)],
        ).getSingleOrNull();
        final key = gidRow?.read<String?>('gid') ?? '${s.id}';
        var next = s.nextDate;
        // Cap catch-up so a years-old start date can't flood the wallet.
        for (var i = 0; i < 36 && !next.isAfter(today); i++) {
          await into(entries).insert(
            EntriesCompanion.insert(
              amountCents: s.amountCents,
              kind: s.kind,
              category: s.category,
              note: Value(s.name),
              account: Value(s.account),
              date: next,
              subscriptionId: Value(s.id),
              importKey: Value('sub:$key:${next.toIso8601String()}'),
            ),
            mode: InsertMode.insertOrIgnore,
          );
          booked++;
          next = addMonths(next, s.periodMonths);
        }
        await (update(
          subscriptions,
        )..where((x) => x.id.equals(s.id))).write(SubscriptionsCompanion(nextDate: Value(next)));
      }
    });
    return booked;
  }

  // Calendar

  Stream<List<Calendar>> watchCalendars() => (select(calendars)..orderBy([(c) => OrderingTerm.asc(c.id)])).watch();

  Future<int> saveCalendar(CalendarsCompanion c) => into(calendars).insertOnConflictUpdate(c);

  Future<void> deleteCalendar(int id) => transaction(() async {
    await (delete(events)..where((e) => e.calendarId.equals(id))).go();
    await (delete(calendars)..where((c) => c.id.equals(id))).go();
  });

  /// Events of visible calendars that could touch [from, to), including
  /// repeating events; expand them with [expandEvents].
  Stream<List<Event>> watchEventsBetween(DateTime from, DateTime to) {
    final q = select(events).join([innerJoin(calendars, calendars.id.equalsExp(events.calendarId))])
      ..where(
        calendars.visible.equals(true) &
            events.start.isSmallerThanValue(to) &
            (events.end.isBiggerOrEqualValue(from) | events.repeat.equals('none').not()),
      );
    return q.map((r) => r.readTable(events)).watch();
  }

  /// Replaces all events of a subscribed calendar with a fresh copy of its feed.
  Future<void> replaceFeedEvents(int calendarId, List<EventsCompanion> rows) => transaction(() async {
    await (delete(events)..where((e) => e.calendarId.equals(calendarId))).go();
    await batch((b) => b.insertAll(events, rows));
    await (update(
      calendars,
    )..where((c) => c.id.equals(calendarId))).write(CalendarsCompanion(syncedAt: Value(DateTime.now())));
  });

  Future<List<Calendar>> feedCalendars() => (select(calendars)..where((c) => c.icsUrl.isNotNull())).get();

  Future<List<Event>> eventsWithReminders() => (select(events)..where((e) => e.remindMinutes.isNotNull())).get();

  Future<int> saveEvent(EventsCompanion e) => into(events).insertOnConflictUpdate(e);

  Future<void> deleteEvent(int id) => (delete(events)..where((e) => e.id.equals(id))).go();

  Future<void> restoreEvent(Event e) => into(events).insert(e, mode: InsertMode.insertOrReplace);

  Future<List<Todo>> todosWithReminders() =>
      (select(todos)..where((t) => t.remindAt.isNotNull() & t.done.equals(false))).get();

  // Spaces

  Stream<List<Space>> watchSpaces() => (select(spaces)..orderBy([(s) => OrderingTerm.asc(s.position)])).watch();

  Future<int> saveSpace(SpacesCompanion s) => into(spaces).insertOnConflictUpdate(s);

  Future<void> deleteSpace(int id) => transaction(() async {
    await (delete(spaceItems)..where((i) => i.spaceId.equals(id))).go();
    await (update(todos)..where((t) => t.spaceId.equals(id))).write(const TodosCompanion(spaceId: Value(null)));
    await (delete(spaces)..where((s) => s.id.equals(id))).go();
  });

  Stream<List<SpaceItem>> watchSpaceItems(int spaceId) =>
      (select(spaceItems)
            ..where((i) => i.spaceId.equals(spaceId))
            ..orderBy([(i) => OrderingTerm.desc(i.pinned), (i) => OrderingTerm.desc(i.updatedAt)]))
          .watch();

  Future<int> saveSpaceItem(SpaceItemsCompanion i) =>
      into(spaceItems).insertOnConflictUpdate(i.copyWith(updatedAt: Value(DateTime.now())));

  Future<void> deleteSpaceItem(int id) => (delete(spaceItems)..where((i) => i.id.equals(id))).go();

  Future<void> restoreSpaceItem(SpaceItem i) => into(spaceItems).insert(i, mode: InsertMode.insertOrReplace);

  Stream<List<Todo>> watchSpaceTodos(int spaceId) =>
      (select(todos)
            ..where((t) => t.spaceId.equals(spaceId))
            ..orderBy([
              (t) => OrderingTerm.asc(t.done),
              (t) => OrderingTerm(expression: t.due, nulls: NullsOrder.last),
              (t) => OrderingTerm.desc(t.createdAt),
            ]))
          .watch();

  // Internships

  Stream<List<Application>> watchApplications() =>
      (select(applications)..orderBy([
            (a) => OrderingTerm(expression: a.deadline, nulls: NullsOrder.last),
            (a) => OrderingTerm.desc(a.updatedAt),
          ]))
          .watch();

  Future<int> saveApplication(ApplicationsCompanion a) =>
      into(applications).insertOnConflictUpdate(a.copyWith(updatedAt: Value(DateTime.now())));

  Future<void> deleteApplication(int id) => (delete(applications)..where((a) => a.id.equals(id))).go();

  Future<void> restoreApplication(Application a) => into(applications).insert(a, mode: InsertMode.insertOrReplace);

  Future<List<Application>> applicationsWithReminders() =>
      (select(applications)..where((a) => a.remindAt.isNotNull() | a.deadline.isNotNull())).get();

  // Work log

  static String dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Stream<List<WorkDay>> watchWorkDays(DateTime from, DateTime to) => (select(
    workDays,
  )..where((w) => w.day.isBiggerOrEqualValue(dayKey(from)) & w.day.isSmallerThanValue(dayKey(to)))).watch();

  Future<void> setWorkDay(DateTime d, String? status, {double? hours, String note = ''}) async {
    if (status == null) {
      await (delete(workDays)..where((w) => w.day.equals(dayKey(d)))).go();
    } else {
      await into(workDays).insertOnConflictUpdate(
        WorkDaysCompanion.insert(day: dayKey(d), status: status, hours: Value(hours), note: Value(note)),
      );
    }
  }

  // Habits

  Stream<List<Habit>> watchHabits() =>
      (select(habits)
            ..where((h) => h.archived.equals(false))
            ..orderBy([(h) => OrderingTerm.asc(h.position), (h) => OrderingTerm.asc(h.id)]))
          .watch();

  Future<int> saveHabit(HabitsCompanion h) => into(habits).insertOnConflictUpdate(h);

  Future<void> deleteHabit(int id) => transaction(() async {
    await (delete(habitChecks)..where((c) => c.habitId.equals(id))).go();
    await (delete(habits)..where((h) => h.id.equals(id))).go();
  });

  /// Checks from [from] on, for streaks and the week view.
  Stream<List<HabitCheck>> watchHabitChecks(DateTime from) =>
      (select(habitChecks)..where((c) => c.day.isBiggerOrEqualValue(dayKey(from)))).watch();

  Future<List<HabitCheck>> habitChecksSince(DateTime from) =>
      (select(habitChecks)..where((c) => c.day.isBiggerOrEqualValue(dayKey(from)))).get();

  Future<void> setHabitDone(int habitId, DateTime day, bool done) async {
    final key = dayKey(day);
    if (done) {
      await into(
        habitChecks,
      ).insert(HabitChecksCompanion.insert(habitId: habitId, day: key), mode: InsertMode.insertOrIgnore);
    } else {
      await (delete(habitChecks)..where((c) => c.habitId.equals(habitId) & c.day.equals(key))).go();
    }
  }

  // Shopping

  Stream<List<ShoppingItem>> watchShopping() =>
      (select(shoppingItems)..orderBy([
            (i) => OrderingTerm.asc(i.done),
            (i) => OrderingTerm.asc(i.store),
            (i) => OrderingTerm.asc(i.id),
          ]))
          .watch();

  Future<int> addShoppingItem(String name, {String quantity = '', String store = '', String category = ''}) =>
      into(shoppingItems).insert(
        ShoppingItemsCompanion.insert(
          name: name,
          quantity: Value(quantity),
          store: Value(store),
          category: Value(category),
        ),
      );

  Future<void> updateShoppingItem(
    int id, {
    String? name,
    String? quantity,
    String? store,
    String? category,
    bool? done,
  }) => (update(shoppingItems)..where((i) => i.id.equals(id))).write(
    ShoppingItemsCompanion(
      name: name == null ? const Value.absent() : Value(name),
      quantity: quantity == null ? const Value.absent() : Value(quantity),
      store: store == null ? const Value.absent() : Value(store),
      category: category == null ? const Value.absent() : Value(category),
      done: done == null ? const Value.absent() : Value(done),
    ),
  );

  Future<void> deleteShoppingItem(int id) => (delete(shoppingItems)..where((i) => i.id.equals(id))).go();

  Future<void> restoreShoppingItem(ShoppingItem i) => into(shoppingItems).insert(i, mode: InsertMode.insertOrReplace);

  Future<int> clearBoughtShopping() => (delete(shoppingItems)..where((i) => i.done.equals(true))).go();

  // Accounts

  Stream<List<Account>> watchAccounts() =>
      (select(accounts)..orderBy([(a) => OrderingTerm.asc(a.position), (a) => OrderingTerm.asc(a.id)])).watch();

  Future<int> saveAccount(AccountsCompanion a) => into(accounts).insertOnConflictUpdate(a);

  Future<void> deleteAccount(int id) => (delete(accounts)..where((a) => a.id.equals(id))).go();

  /// Sets what the account holds right now; entries after this moment move it.
  Future<void> setAccountBalance(int id, int cents, {DateTime? at}) => (update(accounts)..where((a) => a.id.equals(id)))
      .write(AccountsCompanion(balanceCents: Value(cents), balanceAt: Value(at ?? DateTime.now())));

  /// Every entry booked to [name], newest first.
  Stream<List<Entry>> watchAccountEntries(String name) =>
      (select(entries)
            ..where((e) => e.account.lower().equals(name.toLowerCase()))
            ..orderBy([(e) => OrderingTerm.desc(e.date), (e) => OrderingTerm.desc(e.id)]))
          .watch();

  /// Points a recurring payment at an account (empty for none).
  Future<void> setSubscriptionAccount(int id, String account) =>
      (update(subscriptions)..where((s) => s.id.equals(id))).write(SubscriptionsCompanion(account: Value(account)));

  // Savings

  Stream<List<SavingsGoal>> watchGoals() => (select(
    savingsGoals,
  )..orderBy([(g) => OrderingTerm.asc(g.archived), (g) => OrderingTerm.asc(g.createdAt)])).watch();

  Future<int> saveGoal(SavingsGoalsCompanion g) => into(savingsGoals).insertOnConflictUpdate(g);

  Future<void> deleteGoal(int id) => transaction(() async {
    await (delete(savingsMoves)..where((m) => m.goalId.equals(id))).go();
    await (delete(savingsGoals)..where((g) => g.id.equals(id))).go();
  });

  Stream<List<SavingsMove>> watchMoves() =>
      (select(savingsMoves)..orderBy([(m) => OrderingTerm.desc(m.date), (m) => OrderingTerm.desc(m.id)])).watch();

  Future<int> addMove(int goalId, int cents, {String note = '', DateTime? date}) => into(savingsMoves).insert(
    SavingsMovesCompanion.insert(goalId: goalId, amountCents: cents, date: date ?? DateTime.now(), note: Value(note)),
  );

  Future<void> deleteMove(int id) => (delete(savingsMoves)..where((m) => m.id.equals(id))).go();

  // Investing

  Stream<List<Holding>> watchHoldings() => (select(holdings)..orderBy([(h) => OrderingTerm.asc(h.name)])).watch();

  Future<int> saveHolding(HoldingsCompanion h) => into(holdings).insertOnConflictUpdate(h);

  Future<void> deleteHolding(int id) => (delete(holdings)..where((h) => h.id.equals(id))).go();

  Future<void> restoreHolding(Holding h) => into(holdings).insert(h, mode: InsertMode.insertOrReplace);

  Future<void> setHoldingPrice(int id, double price) => (update(
    holdings,
  )..where((h) => h.id.equals(id))).write(HoldingsCompanion(price: Value(price), priceAt: Value(DateTime.now())));

  // Mail

  Stream<List<MailboxAccount>> watchMailAccounts() =>
      (select(mailboxAccounts)..orderBy([(a) => OrderingTerm.asc(a.id)])).watch();

  Future<int> saveMailAccount(MailboxAccountsCompanion a) => into(mailboxAccounts).insertOnConflictUpdate(a);

  Future<void> deleteMailAccount(int id) => (delete(mailboxAccounts)..where((a) => a.id.equals(id))).go();

  // Settings

  Future<Map<String, String>> readSettings() async {
    final rows = await select(settings).get();
    return {for (final r in rows) r.key: r.value};
  }

  Future<void> writeSetting(String key, String value) =>
      into(settings).insertOnConflictUpdate(SettingsCompanion.insert(key: key, value: value));
}

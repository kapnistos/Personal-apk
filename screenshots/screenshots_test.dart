// Renders the main screens with demo data into screenshots/out/.
// Run: flutter test screenshots --update-goldens
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hub/apps/calendar/calendar_page.dart';
import 'package:hub/apps/claude/claude_page.dart';
import 'package:hub/apps/internships/internships_page.dart';
import 'package:hub/apps/news/news_page.dart';
import 'package:hub/apps/news/news_service.dart';
import 'package:hub/apps/spaces/space_page.dart';
import 'package:hub/apps/mail/mail_page.dart';
import 'package:hub/apps/notes/notes_page.dart';
import 'package:hub/apps/todo/todo_page.dart';
import 'package:hub/apps/shopping/shopping_model.dart';
import 'package:hub/apps/shopping/shopping_page.dart';
import 'package:hub/apps/wallet/subscriptions_page.dart';
import 'package:hub/apps/wallet/wallet_page.dart';
import 'package:hub/apps/weather/weather_page.dart';
import 'package:hub/apps/weather/weather_service.dart';
import 'package:hub/core/db/database.dart';
import 'package:hub/core/format.dart';
import 'package:hub/core/settings.dart';
import 'package:hub/core/theme.dart';
import 'package:hub/main.dart';
import 'package:hub/shell/me_page.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

Future<void> loadFonts() async {
  final inter = FontLoader('Inter');
  for (final w in ['Light', 'Regular', 'Medium', 'SemiBold', 'Bold']) {
    inter.addFont(Future.value(ByteData.sublistView(File('assets/fonts/Inter-$w.otf').readAsBytesSync())));
  }
  await inter.load();
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '/opt/flutter';
  final icons = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(
        File('$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf').readAsBytesSync())));
  await icons.load();
}

int cal0(String name, List<Calendar> cals) => cals.firstWhere((c) => c.name == name).id;

Future<void> seed(AppDatabase db, AppSettings settings) async {
  await db.delete(db.todos).go(); // The owner's own tasks stay out of the pictures.
  await settings.setName('Alex');
  final now = DateTime.now();
  final today = dateOnly(now);
  final week = today.subtract(Duration(days: today.weekday - 1));
  final cals = await db.watchCalendars().first;
  final personal = cals[0].id, work = cals[1].id, study = cals[2].id;
  Future<void> ev(int cal, String title, DateTime start, int minutes,
      {String loc = '', String repeat = 'none', bool allDay = false}) async {
    await db.saveEvent(EventsCompanion.insert(
      calendarId: cal,
      title: title,
      start: start,
      end: allDay ? start.add(const Duration(days: 1)) : start.add(Duration(minutes: minutes)),
      location: Value(loc),
      repeat: Value(repeat),
      allDay: Value(allDay),
      remindMinutes: const Value(15),
    ));
  }

  DateTime at(int day, int h, [int m = 0]) => week.add(Duration(days: day, hours: h, minutes: m));
  await ev(study, 'Signals & Systems lecture', at(0, 8, 45), 105, loc: 'Auditorium 4', repeat: 'weekly');
  await ev(work, 'Team stand-up', at(0, 11), 30, repeat: 'daily');
  await ev(study, 'Thermodynamics tutorial', at(1, 13, 30), 90, loc: 'Flux 1.10', repeat: 'weekly');
  await ev(personal, 'Gym', at(1, 18), 75, loc: 'Basic-Fit', repeat: 'weekly');
  await ev(personal, 'Dinner with Eleni', at(2, 19, 30), 120, loc: 'Strijp-S');
  await ev(study, 'Project meeting', at(2, 14), 60);
  await ev(work, 'Design review', at(2, 14, 30), 60);
  await ev(personal, 'Call home', at(3, 20), 30);
  await ev(study, 'Exam week', at(4, 0), 0, allDay: true);
  await ev(personal, 'Flight to Athens', at(5, 9, 40), 210, loc: 'EIN → ATH');
  await ev(personal, 'Haircut', at(3, 10), 45);

  await db.addTodo('Submit CBL report', due: today, important: true);
  await db.addTodo('Pay rent', due: today, remindAt: today.add(const Duration(hours: 18)));
  await db.addTodo('Book train to Schiphol', due: today.add(const Duration(days: 1)));
  await db.addTodo('Renew Proton plan', due: today.add(const Duration(days: 4)));
  await db.addTodo('Buy birthday gift for mum');
  final done = await db.addTodo('Reply to landlord');
  await db.setTodoDone(done, true);

  await db.saveNote(title: 'App ideas', body: 'Widgets for the home screen. Share sheet into Notes. Dark mode schedule.');
  final pinned = await db.saveNote(
      title: 'Wi-Fi and door codes', body: 'Home: see password manager\nBike shed: 4471\nGym locker: 18');
  await db.setNotePinned(pinned, true);
  await db.saveNote(title: 'Thermodynamics', body: 'First law: dU = δQ − δW. Revise entropy examples before Friday.');
  await db.saveNote(title: 'Groceries', body: 'Oats, feta, tomatoes, olive oil, coffee beans');

  final month = DateTime(now.year, now.month);
  Future<void> e(EntryKind k, int cents, String cat, String note, int day, String account) => db.addEntry(
        EntriesCompanion.insert(
          amountCents: cents,
          kind: k,
          category: cat,
          note: Value(note),
          account: Value(account),
          date: month.add(Duration(days: (day - 1).clamp(0, now.day - 1), hours: 12)),
        ),
      );
  await e(EntryKind.income, 245000, 'Salary', 'Monthly salary', 1, 'ABN AMRO');
  await e(EntryKind.expense, 6240, 'Groceries', 'Albert Heijn', 2, 'Revolut');
  await e(EntryKind.expense, 3480, 'Eating out', 'Thuisbezorgd', 4, 'Revolut');
  await e(EntryKind.expense, 2160, 'Transport', 'NS train', 6, 'ABN AMRO');
  await e(EntryKind.tax, 5800, 'Municipal tax', 'Gemeente Eindhoven', 8, 'ABN AMRO');
  await e(EntryKind.expense, 4125, 'Groceries', 'Jumbo', 12, 'Revolut');
  await e(EntryKind.expense, 8999, 'Shopping', 'Coolblue', 15, 'Revolut');
  await e(EntryKind.expense, 1450, 'Health', 'Kruidvat', 20, 'Revolut');
  await e(EntryKind.expense, 2875, 'Groceries', 'Lidl', 27, 'Eurobank');
  await e(EntryKind.expense, 1890, 'Eating out', 'Coffee with friends', 28, 'Revolut');
  // Demo payments only, never a real list.
  await db.delete(db.subscriptions).go();
  await db.setBudget('Groceries', 25000);
  await db.setBudget('Eating out', 8000);
  for (final (name, cents, cat, day, period) in [
    ('Rent', 82500, 'Rent', 1, 1),
    ('Netflix', 1399, 'Streaming', 5, 1),
    ('Spotify', 1199, 'Streaming', 9, 1),
    ('Claude Pro', 2178, 'Software', 14, 1),
    ('Proton Unlimited', 11988, 'Software', 22, 12),
    ('Odido', 2500, 'Phone & internet', 18, 1),
  ]) {
    await db.saveSubscription(SubscriptionsCompanion.insert(
      name: name,
      amountCents: cents,
      kind: EntryKind.subscription,
      category: cat,
      account: Value(cat == 'Rent' ? 'ABN AMRO' : 'Revolut'),
      periodMonths: Value(period),
      nextDate: DateTime(now.year, now.month, day),
    ));
  }
  await db.saveSubscription(SubscriptionsCompanion.insert(
    name: 'Health insurance',
    amountCents: 15100,
    kind: EntryKind.tax,
    category: 'Health insurance',
    nextDate: DateTime(now.year, now.month, 25),
  ));
  await db.bookDueSubscriptions();
  final accounts = await db.watchAccounts().first;
  for (final (i, cents) in [(0, 184250), (1, 94271), (2, 61980)]) {
    await db.setAccountBalance(accounts[i].id, cents, at: month);
  }

  // University, Lab and Job.
  final spaces = await db.watchSpaces().first;
  final allCals = await db.watchCalendars().first;
  int space(String n) => spaces.firstWhere((x) => x.name == n).id;
  Future<void> spaceEvent(String cal, String title, DateTime start, Duration len,
          {bool allDay = false, String where = ''}) =>
      db.saveEvent(EventsCompanion.insert(
        calendarId: cal0(cal, allCals),
        title: title,
        start: start,
        end: start.add(len),
        allDay: Value(allDay),
        location: Value(where),
        remindMinutes: Value(allDay ? 900 : 15),
      ));
  await spaceEvent('Study', 'Thermodynamics exam', addDays(today, 6), const Duration(days: 1), allDay: true, where: 'Aula');
  await spaceEvent('Study', 'Lab report deadline', addDays(today, 12), const Duration(days: 1), allDay: true);
  await spaceEvent('Study', 'Resit window opens', addDays(today, 40), const Duration(days: 1), allDay: true);
  await spaceEvent('Study', 'Fluid mechanics lecture', addDays(today, 1).add(const Duration(hours: 10, minutes: 45)),
      const Duration(hours: 2), where: 'Atlas 0.710');
  await spaceEvent('Study', 'Study group', addDays(today, 3).add(const Duration(hours: 14)), const Duration(hours: 2));
  await spaceEvent('Lab', 'Supervisor meeting', addDays(today, 2).add(const Duration(hours: 9, minutes: 30)),
      const Duration(minutes: 45));
  await spaceEvent('Work', 'Shift', addDays(today, 1).add(const Duration(hours: 17)), const Duration(hours: 5));
  final uni = space('University');
  for (final (t, d, done) in [
    ('Revise chapter 4: entropy', 1, false),
    ('Past exam 2024', 3, false),
    ('Flashcards for formulas', 4, false),
    ('Read chapter 3', -2, true),
  ]) {
    final id = await db.addTodo(t, due: addDays(today, d), spaceId: uni);
    if (done) await db.setTodoDone(id, true);
  }
  await db.saveSpaceItem(SpaceItemsCompanion.insert(
      spaceId: uni, kind: 'link', title: const Value('Canvas course page'), url: const Value('https://canvas.tue.nl')));
  await db.saveSpaceItem(SpaceItemsCompanion.insert(
      spaceId: uni, kind: 'note', title: const Value('Exam rules'), body: const Value('Bring student card. Calculator allowed, no notes.')));
  for (var d = 1; d < now.day; d++) {
    final day = DateTime(now.year, now.month, d);
    if (day.weekday == DateTime.saturday) continue;
    await db.setWorkDay(day, day.weekday == DateTime.sunday ? 'off' : (d == 9 ? 'sick' : (d == 16 ? 'holiday' : 'work')),
        hours: day.weekday >= 6 ? null : 8);
  }

  // Internships.
  for (final (company, role, status, deadline) in [
    ('ASML', 'Software intern, metrology', 'preparing', 3),
    ('Philips Research', 'Data science intern', 'wishlist', 18),
    ('TNO', 'Energy systems intern', 'applied', null),
    ('Shell', 'Graduate internship', 'interview', null),
  ]) {
    await db.saveApplication(ApplicationsCompanion.insert(
      company: company,
      role: Value(role),
      location: const Value('Eindhoven'),
      status: Value(status),
      deadline: Value(deadline == null ? null : addDays(today, deadline)),
      appliedAt: Value(status == 'applied' || status == 'interview' ? addDays(today, -9) : null),
    ));
  }

  // Savings and investing.
  final fund = await db.saveGoal(SavingsGoalsCompanion.insert(name: 'Emergency fund', targetCents: 500000, color: 0xFF1F7A5A));
  final trip = await db.saveGoal(SavingsGoalsCompanion.insert(
      name: 'Summer in Greece', targetCents: 150000, color: 0xFF3A78C9, deadline: Value(DateTime(now.year + 1, 6, 15))));
  await db.addMove(fund, 250000, note: 'Start', date: DateTime(now.year, now.month - 2, 3));
  await db.addMove(fund, 30000, date: DateTime(now.year, now.month, 2));
  await db.addMove(trip, 42000, date: DateTime(now.year, now.month, 2));
  for (final (name, sym, kind, units, invested, price) in [
    ('Vanguard FTSE All-World', 'VWRL.AS', 'etf', 42.0, 470000, 128.40),
    ('iShares Core MSCI EM', 'EMIM.AS', 'etf', 60.0, 180000, 31.95),
    ('Bitcoin', 'BTC-EUR', 'crypto', 0.021, 120000, 61250.0),
  ]) {
    await db.saveHolding(HoldingsCompanion.insert(
        name: name,
        symbol: Value(sym),
        kind: Value(kind),
        units: units,
        investedCents: invested,
        price: price,
        priceAt: Value(now.subtract(const Duration(minutes: 20))),
        account: Value(kind == 'crypto' ? 'Revolut' : 'DEGIRO')));
  }

  // Shopping.
  for (final (name, qty) in [
    ('Pasta', '2x'), ('Deodorant', ''), ('Toilet paper', '24'), ('Feta', ''), ('Tomatoes', '1kg'),
    ('Oat milk', '2l'), ('Chicken thighs', ''), ('Batteries AA', ''), ('Coffee beans', ''),
  ]) {
    await db.addShoppingItem(name, quantity: qty, category: categorize(name), store: suggestStore(name, defaultCheapest, {}));
  }

  // News.
  NewsService.instance
    ..fetchedAt = now.subtract(const Duration(minutes: 4))
    ..items = [
      for (final (i, (title, source, topic)) in [
        ('EU leaders agree on new energy price cap for the winter', 'BBC World', 'General'),
        ('Kabinet presenteert plannen voor betaalbare huurwoningen', 'NOS', 'Netherlands'),
        ('Greece extends digital nomad visa and cuts property tax for young buyers', 'Greek Reporter', 'Greece'),
        ('New open model beats GPT-class systems on reasoning benchmarks', 'Ars Technica', 'AI'),
        ('ECB holds rates steady, signals cut in December', 'CNBC', 'Economy'),
        ('Dutch rail strike called off after late-night deal', 'NL Times', 'Netherlands'),
        ('Wildfire season in Greece ends with lowest burned area in a decade', 'ERT News', 'Greece'),
        ('Astronomers spot water vapour on a temperate super-Earth', 'BBC Science', 'Science'),
        ('Coalition talks resume in The Hague after budget deal', 'Politico Europe', 'Politics'),
        ('Index funds pull in record inflows as rates level off', 'MarketWatch', 'Investing'),
        ('Indoor season preview: who to watch over 60 metres', 'BBC Athletics', 'Sports'),
      ].indexed)
        NewsItem(
          title: title,
          link: 'https://example.com/$i',
          source: source,
          topic: topic,
          summary: 'A short summary of the story so you know what it is about before opening it.',
          published: now.subtract(Duration(minutes: 20 + i * 47)),
        ),
    ];

  // Weather for Amsterdam.
  final h0 = DateTime(now.year, now.month, now.day, now.hour);
  final f = Forecast(
    temperature: 11.4,
    feelsLike: 8.9,
    humidity: 78,
    wind: 21,
    code: 2,
    isDay: true,
    hours: [
      for (var i = 0; i < 24; i++)
        HourForecast(
          time: h0.add(Duration(hours: i)),
          temperature: 11.4 - (i > 6 ? (i - 6) * 0.35 : -i * 0.2),
          code: i < 3 ? 2 : (i < 6 ? 61 : (i < 10 ? 3 : 1)),
          rainChance: i >= 3 && i < 6 ? 65 : 10,
        ),
    ],
    days: [
      for (var d = 0; d < 10; d++)
        DayForecast(
          date: today.add(Duration(days: d)),
          max: <double>[13, 12, 10, 9, 11, 14, 13, 12, 10, 11][d],
          min: <double>[7, 6, 5, 3, 4, 8, 8, 6, 5, 6][d],
          code: [61, 3, 80, 1, 0, 63, 2, 3, 61, 1][d],
          rainChance: [70, 20, 55, 5, 0, 80, 15, 25, 60, 10][d],
          sunrise: today.add(Duration(days: d, hours: 7, minutes: 12 + d)),
          sunset: today.add(Duration(days: d, hours: 17, minutes: 15 - d)),
        ),
    ],
    fetchedAt: DateTime.now(),
  )..source = 'Open-Meteo';
  final n0 = DateTime(now.year, now.month, now.day, now.hour, now.minute - now.minute % 5);
  final n = Nowcast(source: 'Buienradar + Open-Meteo', points: [
    for (var i = 0; i < 24; i++) RainPoint(n0.add(Duration(minutes: 5 * i)), i < 7 ? 0 : (i < 15 ? 0.4 + (i - 7) * 0.35 : 3.2 - (i - 15) * 0.4).clamp(0.0, 9.0).toDouble()),
    for (var i = 1; i <= 8; i++) RainPoint(n0.add(Duration(minutes: 115 + 15 * i)), i < 3 ? 0.3 : 0.0),
  ]);
  WeatherService.instance.seed(52.37403, 4.88969, f, n);
}

void main() {
  setUpAll(loadFonts);

  final shots = <String, Widget Function()?>{
    'home': null,
    'weather': () => const WeatherPage(),
    'calendar': () => const CalendarPage(),
    'todo': () => const TodoPage(),
    'notes': () => const NotesPage(),
    'wallet': () => const WalletPage(),
    'subscriptions': () => const SubscriptionsPage(),
    'claude': () => const ClaudePage(),
    'me': () => const MePage(),
    'mail': () => const MailPage(),
    'university': () => const SpacePage(spaceId: 3),
    'job': () => const SpacePage(spaceId: 1),
    'internships': () => const InternshipsPage(),
    'news': () => const NewsPage(),
    'savings': () => const WalletPage(initialTab: 1),
    'investing': () => const WalletPage(initialTab: 2),
    'shopping': () => const ShoppingPage(),
    'dashboard': null,
  };

  for (final (device, size, dpr) in [('phone', const Size(1080, 2340), 2.625), ('desktop', const Size(1440, 900), 1.0)]) {
    for (final dark in [false, true]) {
      for (final e in shots.entries) {
        if (device == 'desktop' && !['home', 'calendar', 'wallet', 'weather'].contains(e.key)) continue;
        if (e.key == 'dashboard' && device == 'desktop') continue;
        if (dark && !['home', 'calendar', 'wallet', 'todo', 'subscriptions', 'dashboard', 'me'].contains(e.key)) continue;
        testWidgets('$device ${dark ? 'dark' : 'light'} ${e.key}', (tester) async {
          // The whole home screen, top to bottom.
          tester.view.physicalSize = e.key == 'dashboard' ? Size(size.width, 7200) : size;
          tester.view.devicePixelRatio = dpr;
          addTearDown(tester.view.reset);
          final db = AppDatabase(NativeDatabase.memory());
          final settings = AppSettings(db);
          await tester.runAsync(() async {
            await settings.load();
            await seed(db, settings);
            await settings.setThemeMode(dark ? ThemeMode.dark : ThemeMode.light);
          });
          final Widget app = e.value == null
              ? HubApp(db: db, settings: settings)
              : Hub(
                  db: db,
                  settings: settings,
                  child: MaterialApp(
                    debugShowCheckedModeBanner: false,
                    theme: buildTheme(Brightness.light),
                    darkTheme: buildTheme(Brightness.dark),
                    themeMode: settings.themeMode,
                    localizationsDelegates: GlobalMaterialLocalizations.delegates,
                    supportedLocales: const [Locale('en', 'GB')],
                    locale: const Locale('en', 'GB'),
                    home: e.value!(),
                  ),
                );
          await tester.pumpWidget(app);
          for (var i = 0; i < 6; i++) {
            await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 60)));
            await tester.pump(const Duration(milliseconds: 100));
          }
          await expectLater(
            find.byWidget(app),
            matchesGoldenFile('out/$device-${dark ? 'dark' : 'light'}-${e.key}.png'),
          );
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 15));
          await tester.runAsync(db.close);
        });
      }
    }
  }
}

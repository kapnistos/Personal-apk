import 'package:flutter_test/flutter_test.dart';
import 'package:hub/apps/shopping/shopping_model.dart';
import 'package:hub/apps/news/news_service.dart';
import 'package:hub/apps/notes/notes_page.dart';
import 'package:hub/apps/todo/todo_page.dart';
import 'package:hub/apps/wallet/savings_page.dart';
import 'package:hub/core/db/database.dart';

Todo todo(String title, {DateTime? due, DateTime? remindAt, bool done = false}) => Todo(
      id: title.hashCode,
      title: title,
      details: '',
      due: due,
      done: done,
      important: false,
      remindAt: remindAt,
      createdAt: DateTime(2026, 10, 1),
      repeat: 'none',
    );

void main() {
  final now = DateTime(2026, 10, 30, 10); // a Friday morning

  group('quick add', () {
    test('day and time become a due date and reminder', () {
      final q = parseQuickTask('Call the bank tomorrow 18:00', now: now);
      expect(q.title, 'Call the bank');
      expect(q.due, DateTime(2026, 10, 31));
      expect(q.remindAt, DateTime(2026, 10, 31, 18));
    });

    test('a time alone means today, or tomorrow when it has passed', () {
      expect(parseQuickTask('Pay rent at 6pm', now: now).remindAt, DateTime(2026, 10, 30, 18));
      expect(parseQuickTask('Stretch 9:00', now: now).remindAt, DateTime(2026, 10, 31, 9));
    });

    test('repeats and importance', () {
      final q = parseQuickTask('Gym every monday 18:00 !', now: now);
      expect(q.title, 'Gym');
      expect(q.repeat, 'weekly');
      expect(q.important, isTrue);
      expect(q.remindAt, DateTime(2026, 11, 2, 18));
      expect(parseQuickTask('Water plants every day', now: now).repeat, 'daily');
    });

    test('ordinary words are left alone', () {
      expect(parseQuickTask('Read chapter 12', now: now).title, 'Read chapter 12');
      expect(parseQuickTask('Tomorrow', now: now).due, isNull);
      expect(parseQuickTask('Plan the sat', now: now).due, DateTime(2026, 10, 31));
    });
  });

  test('tasks are grouped by when they are due', () {
    final groups = groupTodos([
      todo('late', due: DateTime(2026, 10, 28)),
      todo('today', due: DateTime(2026, 10, 30)),
      todo('reminder today', remindAt: DateTime(2026, 10, 30, 20)),
      todo('later', due: DateTime(2026, 11, 20)),
      todo('whenever'),
    ], now: now);
    expect(groups.map((g) => g.$1), ['Overdue', 'Today', 'Later', 'No date']);
    expect(groups[1].$2.length, 2);
    expect(isTodayTask(todo('r', remindAt: DateTime(2026, 10, 30, 20)), now: now), isTrue);
  });

  test('note checklists count and toggle', () {
    const body = 'Shopping\n- [ ] milk\n- [x] bread';
    expect(checklistCount(body), (1, 2));
    expect(toggleChecklistLine(body, 1), 'Shopping\n- [x] milk\n- [x] bread');
    expect(toggleChecklistLine(body, 2), 'Shopping\n- [ ] milk\n- [ ] bread');
  });

  test('months left for a savings goal', () {
    expect(monthsLeft(DateTime(2027, 6, 1), now: now), 8);
    expect(monthsLeft(DateTime(2026, 10, 31), now: now), 1);
  });

  group('news feeds', () {
    test('RSS items with dates and images', () {
      const rss = '''<?xml version="1.0"?><rss xmlns:media="http://search.yahoo.com/mrss/"><channel>
        <item><title>Storm hits &amp; coast</title><link>https://a.example/1</link>
        <description>&lt;p&gt;Big &lt;b&gt;storm&lt;/b&gt;&lt;/p&gt;</description>
        <pubDate>Fri, 30 Oct 2026 07:12:00 +0100</pubDate>
        <media:thumbnail url="https://img.example/1.jpg"/></item>
      </channel></rss>''';
      final items = parseFeed(rss, const NewsSource('Test', 'x', 'World'));
      expect(items.single.title, 'Storm hits & coast');
      expect(items.single.summary, 'Big storm');
      expect(items.single.image, 'https://img.example/1.jpg');
      expect(items.single.published!.toUtc(), DateTime.utc(2026, 10, 30, 6, 12));
    });

    test('Atom entries', () {
      const atom = '''<feed xmlns="http://www.w3.org/2005/Atom"><entry><title>New chip</title>
        <link rel="alternate" href="https://b.example/2"/><updated>2026-10-30T08:00:00Z</updated>
        <summary>Faster</summary></entry></feed>''';
      final items = parseFeed(atom, const NewsSource('Tech', 'x', 'Tech & AI'));
      expect(items.single.link, 'https://b.example/2');
      expect(items.single.published!.toUtc(), DateTime.utc(2026, 10, 30, 8));
    });

    test('dates in GMT', () {
      expect(parseFeedDate('Thu, 29 Oct 2026 23:05:00 GMT')!.toUtc(), DateTime.utc(2026, 10, 29, 23, 5));
    });
  });

  group('shopping', () {
    test('one line of input becomes items with amounts', () {
      expect(parseShoppingInput('pasta, 2x toilet paper; deodorant\nmilk 2l'), [
        ('pasta', ''),
        ('toilet paper', '2x'),
        ('deodorant', ''),
        ('milk', '2l'),
      ]);
    });

    test('items go to the cheapest shop for their kind', () {
      expect(categorize('Deodorant'), 'Personal care');
      expect(categorize('toilet paper'), 'Paper & cleaning');
      expect(categorize('penne'), 'Pantry');
      expect(categorize('rice'), 'Pantry');
      expect(categorize('eieren'), 'Dairy & eggs');
      expect(suggestStore('pasta', defaultCheapest, {}), 'Albert Heijn');
      expect(suggestStore('deodorant', defaultCheapest, {}), 'Kruidvat');
      expect(suggestStore('toilet paper', defaultCheapest, {}), 'Lidl');
      expect(suggestStore('Pasta', defaultCheapest, {'pasta': 'Jumbo'}), 'Jumbo');
    });

    test("Claude's answer is read back, in either layout", () {
      final items = ['Pasta', 'deodorant', 'toilet paper'];
      expect(parseStorePlan('Pasta → Albert Heijn\n- deodorant -> Kruidvat\ntoilet paper: Lidl (bulk)', items),
          {'pasta': 'Albert Heijn', 'deodorant': 'Kruidvat', 'toilet paper': 'Lidl'});
      expect(parseStorePlan('**Lidl**\n- toilet paper\n- pasta\n\nKruidvat:\n- deodorant', items),
          {'toilet paper': 'Lidl', 'pasta': 'Lidl', 'deodorant': 'Kruidvat'});
    });
  });
}

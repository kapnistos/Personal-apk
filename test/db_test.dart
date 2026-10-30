import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hub/core/db/database.dart';
import 'package:hub/core/settings.dart';

void main() {
  test('database opens and seeds', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final settings = AppSettings(db);
    await settings.load();
    final cities = await db.watchCities().first;
    expect(cities.single.name, 'Amsterdam');
    expect((await db.watchCalendars().first).length, 4);
    await db.close();
  });
}

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hub/apps/spaces/my_spaces.dart';
import 'package:hub/core/db/database.dart';

void main() {
  test('your own spaces become Home apps; built-in ones do not', () async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.saveSpace(SpacesCompanion.insert(name: 'Gym', icon: const Value('sport'), color: 0xFF1F9D6B));
    final apps = customSpaceApps(await db.watchSpaces().first);
    expect(apps.map((a) => a.title), ['Gym']);
    expect(apps.single.id, startsWith('space:'));
    await db.close();
  });
}

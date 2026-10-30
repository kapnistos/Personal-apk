import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hub/apps/registry.dart';
import 'package:hub/apps/spaces/my_spaces.dart';
import 'package:hub/core/db/database.dart';
import 'package:hub/core/edition.dart';

void main() {
  test('the public build shows Internships only once imported data has some', () async {
    final was = personalEdition;
    personalEdition = false;
    addTearDown(() {
      personalEdition = was;
      hasInternshipData = false;
    });
    final db = AppDatabase(NativeDatabase.memory());
    await checkImportedApps(db);
    expect(miniApps.map((a) => a.id), isNot(contains('internships')));
    await db.customStatement(
      "INSERT INTO applications (company, role, status, updated_at) VALUES ('Acme', 'Intern', 'applied', 0)",
    );
    await checkImportedApps(db);
    expect(miniApps.map((a) => a.id), contains('internships'));
    expect(miniApps.map((a) => a.id), isNot(contains('lab')));
    await db.close();
  });

  test('a Lab space imported into the public build shows up as your own space', () {
    const lab = Space(id: 9, name: 'Lab research', icon: 'science', color: 0, position: 3);
    final was = personalEdition;
    personalEdition = false;
    addTearDown(() => personalEdition = was);
    expect(spaceShown(lab), isTrue);
    expect(customSpaceApps([lab]).map((a) => a.title), ['Lab research']);
  });

  test('your own spaces become Home apps; built-in ones do not', () async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.saveSpace(SpacesCompanion.insert(name: 'Gym', icon: const Value('sport'), color: 0xFF1F9D6B));
    final apps = customSpaceApps(await db.watchSpaces().first);
    expect(apps.map((a) => a.title), ['Gym']);
    expect(apps.single.id, startsWith('space:'));
    await db.close();
  });
}

import 'db/database.dart';

/// The public build: Lab and Internships stay hidden unless imported data has them.
// Not const so the screenshots can show the public build.
var personalEdition = false;

/// Mini-apps and Home widgets only the owner's build shows.
const personalOnlyApps = {'lab', 'internships'};
const personalOnlyWidgets = {'deadlines'};

/// The public build shows Internships only once imported data has some.
var hasInternshipData = false;

Future<void> checkImportedApps(AppDatabase db) async {
  final n = await db.customSelect('SELECT COUNT(*) AS n FROM applications').getSingle();
  hasInternshipData = n.read<int>('n') > 0;
}

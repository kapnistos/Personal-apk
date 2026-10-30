import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../../core/db/database.dart';
import '../../core/edition.dart';
import '../../core/mini_app.dart';
import '../../core/press.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'space_page.dart';

/// Spaces that come with the app; everything else is one the user made.
/// The public build never makes a Lab space, so one there was brought in by an import and counts as the user's own.
Set<String> get builtInSpaces => {'Job', if (personalEdition) 'Lab research', 'University'};

/// Icons a space can use.
const mySpaceIcons = <String, IconData>{
  'folder': Icons.folder_rounded,
  'work': Icons.work_rounded,
  'school': Icons.school_rounded,
  'science': Icons.science_rounded,
  'sport': Icons.fitness_center_rounded,
  'home': Icons.home_rounded,
  'travel': Icons.flight_rounded,
  'music': Icons.music_note_rounded,
  'code': Icons.code_rounded,
  'health': Icons.favorite_rounded,
  'pets': Icons.pets_rounded,
  'book': Icons.menu_book_rounded,
  'car': Icons.directions_car_rounded,
  'money': Icons.savings_rounded,
  'family': Icons.family_restroom_rounded,
  'star': Icons.star_rounded,
};

const mySpaceColors = [0xFF4F86FF, 0xFF1F9D6B, 0xFFD9822B, 0xFFC0563F, 0xFF7A5BC0, 0xFF2D8C9E, 0xFFB5487A, 0xFF5F6B7A];

IconData mySpaceIcon(String key) => mySpaceIcons[key] ?? Icons.folder_rounded;

/// Whether this build shows the space. Every space is shown: an imported Lab space must not vanish.
bool spaceShown(Space s) => true;

/// The user's own spaces as Home tiles.
List<MiniApp> customSpaceApps(List<Space> spaces) => [
  for (final s in spaces)
    if (!builtInSpaces.contains(s.name))
      MiniApp(
        id: 'space:${s.id}',
        title: s.name,
        subtitle: 'Your space',
        icon: mySpaceIcon(s.icon),
        color: Color(s.color),
        builder: (_) => SpacePage(spaceId: s.id),
      ),
];

/// Every space, built-in and your own, with a button to make a new one.
class SpacesPage extends StatelessWidget {
  const SpacesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Scaffold(
      appBar: HubBar(title: const Text('Spaces')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => editSpace(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New space'),
      ),
      body: StreamBuilder<List<Space>>(
        stream: context.db.watchSpaces(),
        builder: (context, snap) {
          final spaces = (snap.data ?? const <Space>[]).where(spaceShown).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
            children: [
              ContentWidth(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                  child: Text(
                    'A space keeps dates, meetings, a plan and saved notes and links together, '
                    'with its own calendar. Your own spaces also appear on Home.',
                    style: TextStyle(color: p.muted, height: 1.4),
                  ),
                ),
              ),
              ContentWidth(
                child: GroupCard(
                  indent: 72,
                  children: [
                    for (final s in spaces)
                      Press(
                        child: ListTile(
                          leading: AppGlyph(icon: mySpaceIcon(s.icon), color: Color(s.color), size: 40),
                          title: Text(s.name),
                          subtitle: Text(builtInSpaces.contains(s.name) ? 'Comes with Hub' : 'Your space'),
                          trailing: IconButton(
                            tooltip: 'Edit',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => editSpace(context, space: s),
                          ),
                          onTap: () =>
                              Navigator.of(context).push(MaterialPageRoute(builder: (_) => SpacePage(spaceId: s.id))),
                        ),
                      ),
                    if (spaces.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('No spaces yet')),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Make a new space, or rename, recolour or delete one.
Future<void> editSpace(BuildContext context, {Space? space}) async {
  final db = context.db;
  final name = TextEditingController(text: space?.name ?? '');
  var icon = space?.icon ?? 'folder';
  var color = space?.color ?? mySpaceColors.first;
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(ctx).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(space == null ? 'New space' : 'Edit space', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 14),
            TextField(
              controller: name,
              autofocus: space == null,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Name, like Gym, Travel or Side project'),
            ),
            const SizedBox(height: 16),
            const SectionLabel('Icon'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in mySpaceIcons.entries)
                  ChoiceChip(
                    // A chosen chip is filled with the ink colour, so its icon flips to stay visible.
                    label: Icon(
                      e.value,
                      size: 20,
                      color: icon == e.key ? Palette.of(ctx).background : Palette.of(ctx).ink,
                    ),
                    selected: icon == e.key,
                    onSelected: (_) => setSheet(() => icon = e.key),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const SectionLabel('Colour'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final c in mySpaceColors)
                  GestureDetector(
                    onTap: () => setSheet(() => color = c),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                        border: color == c ? Border.all(color: Palette.of(ctx).ink, width: 3) : null,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                if (space != null)
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: Palette.of(ctx).danger),
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: ctx,
                        builder: (d) => AlertDialog(
                          title: Text('Delete ${space.name}?'),
                          content: const Text('Its saved items go too. Tasks stay, without the space.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
                            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Delete')),
                          ],
                        ),
                      );
                      if (ok != true) return;
                      await db.deleteSpace(space.id);
                      if (ctx.mounted) Navigator.pop(ctx, false);
                    },
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('Delete'),
                  ),
                const Spacer(),
                ListenableBuilder(
                  listenable: name,
                  builder: (ctx, _) => FilledButton(
                    onPressed: name.text.trim().isEmpty ? null : () => Navigator.pop(ctx, true),
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  // The controller is left to the garbage collector: the sheet still draws the field while it slides away.
  final title = name.text.trim();
  if (saved != true || title.isEmpty) return;
  if (space == null) {
    final all = await db.watchSpaces().first;
    final calendarId = await db.saveCalendar(CalendarsCompanion.insert(name: title, color: color));
    await db.saveSpace(
      SpacesCompanion.insert(
        name: title,
        icon: Value(icon),
        color: color,
        calendarId: Value(calendarId),
        position: Value(all.length),
      ),
    );
  } else {
    await db.saveSpace(space.toCompanion(false).copyWith(name: Value(title), icon: Value(icon), color: Value(color)));
  }
}

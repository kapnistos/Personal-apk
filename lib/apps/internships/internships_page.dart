import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/db/database.dart';
import '../../core/format.dart';
import '../../core/reminders.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

const internshipColor = Color(0xFF2F6F8F);

/// The steps of an application, in order.
const applicationStatuses = ['wishlist', 'preparing', 'applied', 'interview', 'offer', 'rejected'];

const applicationLabels = {
  'wishlist': 'To apply',
  'preparing': 'Preparing',
  'applied': 'Applied',
  'interview': 'Interview',
  'offer': 'Offer',
  'rejected': 'Closed',
};

const applicationColors = {
  'wishlist': Color(0xFF6F6A60),
  'preparing': Color(0xFFCF9418),
  'applied': Color(0xFF3A78C9),
  'interview': Color(0xFF6650AE),
  'offer': Color(0xFF1F7A5A),
  'rejected': Color(0xFFA0968A),
};

/// A starting checklist for the notes of a new application.
const applicationChecklist = '- [ ] CV updated\n- [ ] Motivation letter\n- [ ] Transcript\n- [ ] References';

class InternshipsPage extends StatefulWidget {
  const InternshipsPage({super.key});

  @override
  State<InternshipsPage> createState() => _InternshipsPageState();
}

class _InternshipsPageState extends State<InternshipsPage> {
  String? _status;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Internships')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: internshipColor,
        foregroundColor: Colors.white,
        onPressed: () => editApplication(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add'),
      ),
      body: StreamBuilder<List<Application>>(
        stream: context.db.watchApplications(),
        builder: (context, snap) {
          final all = snap.data ?? const <Application>[];
          final counts = <String, int>{};
          for (final a in all) {
            counts[a.status] = (counts[a.status] ?? 0) + 1;
          }
          final shown = _status == null
              ? all.where((a) => a.status != 'rejected').toList()
              : all.where((a) => a.status == _status).toList();
          final today = dateOnly(DateTime.now());
          final soon = all
              .where((a) =>
                  (a.status == 'wishlist' || a.status == 'preparing') &&
                  a.deadline != null &&
                  daysBetween(today, a.deadline!) >= 0 &&
                  daysBetween(today, a.deadline!) <= 7)
              .toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
            children: [
              ContentWidth(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
                    child: Row(children: [
                      for (final s in applicationStatuses.take(5))
                        Expanded(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => setState(() => _status = _status == s ? null : s),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Column(children: [
                                Text('${counts[s] ?? 0}',
                                    style: TextStyle(
                                        fontSize: 22, fontWeight: FontWeight.w700, color: applicationColors[s])),
                                const SizedBox(height: 2),
                                Text(applicationLabels[s]!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 12.5,
                                        color: _status == s ? p.ink : p.muted,
                                        fontWeight: _status == s ? FontWeight.w700 : FontWeight.w500)),
                              ]),
                            ),
                          ),
                        ),
                    ]),
                  ),
                ),
              ),
              if (soon.isNotEmpty && _status == null) ...[
                const SizedBox(height: 10),
                ContentWidth(
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFCF9418).withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(children: [
                      const Icon(Icons.alarm_rounded, color: Color(0xFFB07D10)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Apply this week: ${soon.map((a) => '${a.company} (${friendlyDay(a.deadline!)})').join(', ')}',
                          style: const TextStyle(height: 1.35),
                        ),
                      ),
                    ]),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              SizedBox(
                height: 40,
                child: ContentWidth(
                  child: ListView(scrollDirection: Axis.horizontal, children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        showCheckmark: false,
                        label: const Text('Open'),
                        selected: _status == null,
                        onSelected: (_) => setState(() => _status = null),
                      ),
                    ),
                    for (final s in applicationStatuses)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          showCheckmark: false,
                          label: Text(applicationLabels[s]!),
                          selected: _status == s,
                          onSelected: (_) => setState(() => _status = s),
                        ),
                      ),
                  ]),
                ),
              ),
              const SizedBox(height: 6),
              if (shown.isEmpty)
                EmptyState(
                  icon: Icons.work_outline_rounded,
                  title: all.isEmpty ? 'Start your list' : 'Nothing here',
                  message: all.isEmpty
                      ? 'Add internships you want to apply to, with the deadline. Hub reminds you two days before, '
                          'and whenever you set a reminder.'
                      : 'No applications with this status.',
                ),
              for (final a in shown)
                ContentWidth(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: ApplicationCard(a: a),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class ApplicationCard extends StatelessWidget {
  const ApplicationCard({super.key, required this.a});
  final Application a;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final color = applicationColors[a.status]!;
    final today = dateOnly(DateTime.now());
    final left = a.deadline == null ? null : daysBetween(today, a.deadline!);
    final open = a.status == 'wishlist' || a.status == 'preparing';
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => editApplication(context, application: a),
        child: Container(
          decoration: BoxDecoration(border: Border(left: BorderSide(color: color, width: 4))),
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(a.company, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  if (a.role.isNotEmpty || a.location.isNotEmpty)
                    Text([a.role, a.location].where((s) => s.isNotEmpty).join(' · '),
                        style: TextStyle(color: p.muted)),
                ]),
              ),
              if (a.favourite) const Icon(Icons.star_rounded, color: Color(0xFFE0A526), size: 20),
              PopupMenuButton<String>(
                tooltip: 'Move to',
                onSelected: (s) => context.db.saveApplication(a.toCompanion(false).copyWith(
                      status: Value(s),
                      appliedAt: Value(s == 'applied' && a.appliedAt == null ? DateTime.now() : a.appliedAt),
                    )),
                itemBuilder: (_) => [
                  for (final s in applicationStatuses)
                    PopupMenuItem(
                      value: s,
                      child: Row(children: [
                        CircleAvatar(radius: 5, backgroundColor: applicationColors[s]),
                        const SizedBox(width: 10),
                        Text(applicationLabels[s]!),
                      ]),
                    ),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  margin: const EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(20)),
                  child: Text(applicationLabels[a.status]!,
                      style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13.5)),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 14, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              if (a.deadline != null)
                _Meta(
                  icon: Icons.flag_outlined,
                  text: 'Deadline ${DateFormat('d MMM').format(a.deadline!)}'
                      '${open && left != null ? (left < 0 ? ' · passed' : left == 0 ? ' · today' : ' · $left days left') : ''}',
                  color: open && left != null && left <= 3 ? p.danger : null,
                ),
              if (a.remindAt != null && a.remindAt!.isAfter(DateTime.now()))
                _Meta(
                    icon: Icons.notifications_none_rounded,
                    text: '${friendlyDay(a.remindAt!)} ${DateFormat.Hm().format(a.remindAt!)}'),
              if (a.appliedAt != null) _Meta(icon: Icons.send_outlined, text: 'Applied ${friendlyDay(a.appliedAt!)}'),
              if (a.url.isNotEmpty)
                InkWell(
                  onTap: () => launchUrl(Uri.parse(a.url.contains('://') ? a.url : 'https://${a.url}'),
                      mode: LaunchMode.externalApplication),
                  child: const _Meta(icon: Icons.open_in_new_rounded, text: 'Posting', color: internshipColor),
                ),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text, this.color});
  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Palette.of(context).muted;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 15, color: c),
      const SizedBox(width: 4),
      Text(text, style: TextStyle(fontSize: 13.5, color: c)),
    ]);
  }
}

Future<void> editApplication(BuildContext context, {Application? application}) {
  return Navigator.of(context).push(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => Hub(db: context.db, settings: context.settings, child: _ApplicationEditor(a: application)),
  ));
}

class _ApplicationEditor extends StatefulWidget {
  const _ApplicationEditor({this.a});
  final Application? a;

  @override
  State<_ApplicationEditor> createState() => _ApplicationEditorState();
}

class _ApplicationEditorState extends State<_ApplicationEditor> {
  late final _company = TextEditingController(text: widget.a?.company ?? '');
  late final _role = TextEditingController(text: widget.a?.role ?? '');
  late final _location = TextEditingController(text: widget.a?.location ?? '');
  late final _url = TextEditingController(text: widget.a?.url ?? '');
  late final _notes = TextEditingController(text: widget.a?.notes ?? applicationChecklist);
  late String _status = widget.a?.status ?? 'wishlist';
  late DateTime? _deadline = widget.a?.deadline;
  late DateTime? _remind = widget.a?.remindAt;
  late bool _favourite = widget.a?.favourite ?? false;

  @override
  void dispose() {
    for (final c in [_company, _role, _location, _url, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_company.text.trim().isEmpty) return;
    final a = widget.a;
    await context.db.saveApplication(ApplicationsCompanion(
      id: a == null ? const Value.absent() : Value(a.id),
      company: Value(_company.text.trim()),
      role: Value(_role.text.trim()),
      location: Value(_location.text.trim()),
      url: Value(_url.text.trim()),
      status: Value(_status),
      deadline: Value(_deadline),
      remindAt: Value(_remind),
      appliedAt: Value(_status == 'applied' && a?.appliedAt == null ? DateTime.now() : a?.appliedAt),
      notes: Value(_notes.text.trim()),
      favourite: Value(_favourite),
      createdAt: a == null ? const Value.absent() : Value(a.createdAt),
    ));
    if (_remind != null || _deadline != null) await Reminders.instance.ensurePermission();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _pickRemind() async {
    final now = DateTime.now();
    final base = _remind ?? DateTime(now.year, now.month, now.day + 1, 10);
    final day = await showDatePicker(
        context: context, initialDate: base, firstDate: dateOnly(now), lastDate: DateTime(now.year + 3));
    if (day == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(base));
    if (t == null) return;
    setState(() => _remind = DateTime(day.year, day.month, day.day, t.hour, t.minute));
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.a == null ? 'New internship' : 'Internship'),
        actions: [
          IconButton(
            tooltip: _favourite ? 'Unmark favourite' : 'Favourite',
            icon: Icon(_favourite ? Icons.star_rounded : Icons.star_outline_rounded,
                color: _favourite ? const Color(0xFFE0A526) : null),
            onPressed: () => setState(() => _favourite = !_favourite),
          ),
          if (widget.a != null)
            IconButton(
              tooltip: 'Delete',
              icon: Icon(Icons.delete_outline_rounded, color: p.danger),
              onPressed: () {
                final db = context.db;
                final a = widget.a!;
                final messenger = ScaffoldMessenger.of(context);
                db.deleteApplication(a.id);
                Navigator.pop(context);
                messenger.showSnackBar(SnackBar(
                  content: Text('${a.company} deleted'),
                  action: SnackBarAction(label: 'Undo', onPressed: () => db.restoreApplication(a)),
                ));
              },
            ),
          Padding(
            padding: const EdgeInsets.only(right: 12, left: 4),
            child: FilledButton(onPressed: _save, child: const Text('Save')),
          ),
        ],
      ),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            TextField(
              controller: _company,
              autofocus: widget.a == null,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Company or lab'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _role,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Role', hintText: 'Research intern, data science'),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _location,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Where'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _url,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(labelText: 'Link to posting'),
                ),
              ),
            ]),
            const SizedBox(height: 16),
            const SectionLabel('Status'),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final s in applicationStatuses)
                ChoiceChip(
                  showCheckmark: false,
                  avatar: CircleAvatar(radius: 5, backgroundColor: applicationColors[s]),
                  label: Text(applicationLabels[s]!),
                  selected: _status == s,
                  onSelected: (_) => setState(() => _status = s),
                ),
            ]),
            const SizedBox(height: 16),
            Wrap(spacing: 8, runSpacing: 8, children: [
              InputChip(
                avatar: Icon(Icons.flag_outlined, size: 18, color: p.muted),
                label: Text(_deadline == null ? 'Add deadline' : 'Deadline ${DateFormat('d MMM y').format(_deadline!)}'),
                onPressed: () async {
                  final now = DateTime.now();
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _deadline ?? addDays(dateOnly(now), 14),
                    firstDate: DateTime(now.year - 1),
                    lastDate: DateTime(now.year + 3),
                  );
                  if (d != null) setState(() => _deadline = d);
                },
                onDeleted: _deadline == null ? null : () => setState(() => _deadline = null),
              ),
              InputChip(
                avatar: Icon(Icons.notifications_none_rounded, size: 18, color: p.muted),
                label: Text(_remind == null
                    ? 'Remind me'
                    : '${friendlyDay(_remind!)} ${DateFormat.Hm().format(_remind!)}'),
                onPressed: _pickRemind,
                onDeleted: _remind == null ? null : () => setState(() => _remind = null),
              ),
            ]),
            if (_deadline != null && (_status == 'wishlist' || _status == 'preparing'))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('You also get a reminder two days before the deadline, at 9:00.',
                    style: TextStyle(color: p.muted, fontSize: 13.5)),
              ),
            const SizedBox(height: 16),
            TextField(
              controller: _notes,
              minLines: 6,
              maxLines: 20,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Notes',
                alignLabelWithHint: true,
                hintText: 'What they ask for, contacts, interview questions',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

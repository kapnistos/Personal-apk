import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/db/database.dart';
import '../../core/format.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'wallet_model.dart';

/// Twelve months side by side: what came in, what went out, taxes and savings rate.
class YearPage extends StatefulWidget {
  const YearPage({super.key});

  @override
  State<YearPage> createState() => _YearPageState();
}

class _YearPageState extends State<YearPage> {
  int _year = DateTime.now().year;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final currency = context.settings.currency;
    return Scaffold(
      appBar: AppBar(
        title: Text('$_year'),
        actions: [
          IconButton(
              tooltip: 'Previous year',
              onPressed: () => setState(() => _year--),
              icon: const Icon(Icons.chevron_left_rounded)),
          IconButton(
              tooltip: 'Next year',
              onPressed: _year >= DateTime.now().year ? null : () => setState(() => _year++),
              icon: const Icon(Icons.chevron_right_rounded)),
          const SizedBox(width: 8),
        ],
      ),
      body: StreamBuilder<List<Entry>>(
        stream: context.db.watchEntries(DateTime(_year), DateTime(_year + 1)),
        builder: (context, snap) {
          final entries = (snap.data ?? const <Entry>[]).where((e) => e.date.year == _year).toList();
          final year = MonthSummary(entries);
          final taxes = year.byKind[EntryKind.tax] ?? 0;
          final rate = year.income == 0 ? null : (year.net / year.income * 100);
          final months = [
            for (var m = 1; m <= 12; m++)
              (m, MonthSummary(entries.where((e) => e.date.month == m).toList())),
          ];
          final taxByCategory = <String, int>{};
          for (final e in entries.where((e) => e.kind == EntryKind.tax)) {
            taxByCategory[e.category] = (taxByCategory[e.category] ?? 0) + e.amountCents;
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              ContentWidth(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Wrap(spacing: 24, runSpacing: 14, children: [
                      _Stat('Came in', money(year.income, currency), p.positive),
                      _Stat('Went out', money(year.out, currency), p.danger),
                      _Stat('Left over', money(year.net, currency, signed: true), p.ink),
                      _Stat('Taxes', money(taxes, currency), const Color(0xFF7A4E9E)),
                      if (rate != null) _Stat('Savings rate', '${rate.toStringAsFixed(0)}%', TileColors.finance),
                    ]),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ContentWidth(
                child: Section(
                  title: 'Month by month',
                  child: Column(children: [
                    for (final (m, s) in months)
                      if (s.income != 0 || s.out != 0)
                        ListTile(
                          dense: true,
                          title: Text(DateFormat.MMMM().format(DateTime(_year, m))),
                          subtitle: Text('In ${money(s.income, currency)} · Out ${money(s.out, currency)}',
                              style: TextStyle(color: p.muted)),
                          trailing: Text(money(s.net, currency, signed: true),
                              style: TextStyle(
                                  fontWeight: FontWeight.w600, color: s.net >= 0 ? p.positive : p.danger)),
                        ),
                    if (months.every((x) => x.$2.income == 0 && x.$2.out == 0))
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        child: Text('No entries in $_year.', style: TextStyle(color: p.muted)),
                      ),
                    const SizedBox(height: 6),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              ContentWidth(
                child: Section(
                  title: 'Taxes paid',
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    for (final MapEntry(key: k, value: v) in taxByCategory.entries)
                      ListTile(
                        dense: true,
                        leading: Icon(categoryInfo(k).icon, color: categoryInfo(k).color),
                        title: Text(k),
                        trailing: Text(money(v, currency)),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      child: Text(
                        taxByCategory.isEmpty
                            ? 'Add taxes as "Tax" entries to see them here. Handy for the yearly '
                                'aangifte in the Netherlands and the Greek E1.'
                            : 'Useful for your yearly tax return. Export the year as CSV from the Wallet menu.',
                        style: TextStyle(color: p.muted, fontSize: 14),
                      ),
                    ),
                  ]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.color);
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionLabel(label),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: color)),
      ]);
}

/// Every wallet entry as CSV, readable by Excel and Google Sheets.
String entriesToCsv(List<Entry> entries) {
  String q(String s) => '"${s.replaceAll('"', '""')}"';
  final b = StringBuffer('date,kind,category,amount,note,account\n');
  for (final e in entries) {
    b.writeln([
      DateFormat('yyyy-MM-dd').format(e.date),
      e.kind.name,
      q(e.category),
      (e.kind.sign * e.amountCents / 100).toStringAsFixed(2),
      q(e.note),
      q(e.account),
    ].join(','));
  }
  return b.toString();
}

Future<void> exportEntries(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final entries = await context.db.watchEntries(DateTime(2000), DateTime(2100)).first;
  final csv = entriesToCsv(entries);
  try {
    final bytes = Uint8List.fromList(utf8.encode(csv));
    final saved = await FilePicker.saveFile(
      dialogTitle: 'Save wallet export',
      fileName: 'hub-wallet-${DateFormat('yyyy-MM-dd').format(DateTime.now())}.csv',
      bytes: bytes,
      mimeType: 'text/csv',
    );
    if (saved == null) return;
    messenger.showSnackBar(SnackBar(content: Text('Saved ${entries.length} entries')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Could not save: $e')));
  }
}

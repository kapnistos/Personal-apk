import 'package:csv/csv.dart';

import '../../core/db/database.dart';

/// A transaction read from a bank export, before it is saved.
class ImportedTx {
  ImportedTx({
    required this.date,
    required this.amountCents,
    required this.description,
    required this.account,
    required this.key,
  });

  final DateTime date;

  /// Signed: negative is money out.
  final int amountCents;
  final String description;
  final String account;

  /// Stable id so importing the same file twice adds nothing.
  final String key;

  EntryKind get kind => guessKind(description, amountCents);
  String get category => guessCategory(description, kind);
}

class ImportResult {
  ImportResult(this.format, this.rows);
  final String format;
  final List<ImportedTx> rows;
}

class ImportException implements Exception {
  ImportException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Reads exports from Revolut (CSV), ABN AMRO (TXT, tab separated) and
/// Eurobank or any other bank (CSV with a header row).
ImportResult parseBankExport(String text, {String fileName = ''}) {
  final clean = text.replaceFirst('﻿', '').trim();
  if (clean.isEmpty) throw ImportException('The file is empty.');
  final firstLine = clean.split(RegExp(r'\r?\n')).first;
  final delimiter = _guessDelimiter(firstLine);
  final rows = Csv(fieldDelimiter: delimiter, autoDetect: false)
      .decode(clean)
      .map((r) => r.map((c) => '$c'.trim()).toList())
      .where((r) => r.any((c) => c.isNotEmpty))
      .toList();
  if (rows.isEmpty) throw ImportException('No rows found.');

  final header = rows.first.map((h) => h.toLowerCase()).toList();
  if (header.contains('started date') && header.contains('amount') && header.contains('state')) {
    return ImportResult('Revolut', _revolut(rows));
  }
  if (delimiter == '\t' && rows.first.length >= 8 && RegExp(r'^\d{8}$').hasMatch(rows.first[2])) {
    return ImportResult('ABN AMRO', _abnTxt(rows));
  }
  return ImportResult(_looksGreek(header) ? 'Eurobank' : 'Bank CSV', _generic(rows, fileName));
}

String _guessDelimiter(String line) {
  final counts = {for (final d in ['\t', ';', ',']) d: d.allMatches(line).length};
  return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
}

bool _looksGreek(List<String> header) => header.any((h) => RegExp(r'[Ͱ-Ͽ]').hasMatch(h));

List<ImportedTx> _revolut(List<List<String>> rows) {
  final h = rows.first.map((x) => x.toLowerCase()).toList();
  int col(String name) => h.indexOf(name);
  final iType = col('type'), iDate = col('started date'), iDone = col('completed date');
  final iDesc = col('description'), iAmount = col('amount'), iFee = col('fee');
  final iState = col('state'), iCur = col('currency'), iProduct = col('product');
  final out = <ImportedTx>[];
  for (final r in rows.skip(1)) {
    if (r.length < h.length) continue;
    final state = r[iState].toUpperCase();
    if (state != 'COMPLETED') continue;
    final date = DateTime.tryParse(r[iDone].isNotEmpty ? r[iDone] : r[iDate]);
    final amount = parseAmount(r[iAmount]);
    if (date == null || amount == null) continue;
    final fee = iFee >= 0 ? (parseAmount(r[iFee]) ?? 0) : 0;
    final type = iType >= 0 ? r[iType] : '';
    final product = iProduct >= 0 ? r[iProduct] : '';
    out.add(ImportedTx(
      date: date,
      amountCents: amount - fee,
      description: type.toUpperCase() == 'TOPUP' ? 'Top-up: ${r[iDesc]}' : r[iDesc],
      account: 'Revolut${product.isNotEmpty && product != 'Current' ? ' $product' : ''}'
          '${iCur >= 0 && r[iCur] != 'EUR' ? ' ${r[iCur]}' : ''}',
      key: 'revolut:${r[iDate]}:${r[iAmount]}:${r[iDesc]}',
    ));
  }
  return out;
}

/// ABN AMRO "TXT" export columns: account, currency, date (yyyymmdd),
/// start balance, end balance, interest date, amount ("-12,50"), description.
List<ImportedTx> _abnTxt(List<List<String>> rows) {
  final out = <ImportedTx>[];
  for (final r in rows) {
    if (r.length < 8) continue;
    final d = r[2];
    final date = DateTime.tryParse('${d.substring(0, 4)}-${d.substring(4, 6)}-${d.substring(6, 8)}');
    final amount = parseAmount(r[6]);
    if (date == null || amount == null) continue;
    final desc = cleanAbnDescription(r.sublist(7).join(' '));
    out.add(ImportedTx(
      date: date,
      amountCents: amount,
      description: desc,
      account: 'ABN AMRO',
      key: 'abn:${r[0]}:${r[2]}:${r[3]}:${r[6]}',
    ));
  }
  return out;
}

/// Pulls the readable name out of ABN AMRO's SEPA description blob.
String cleanAbnDescription(String raw) {
  final name = RegExp(r'/NAME/([^/]+)').firstMatch(raw) ?? RegExp(r'Naam:\s*(.+?)\s{2,}').firstMatch(raw);
  final remi = RegExp(r'/REMI/([^/]+)').firstMatch(raw) ?? RegExp(r'Omschrijving:\s*(.+?)\s{2,}').firstMatch(raw);
  final pas = RegExp(r'BEA.*?(?:,PAS\d+|\d{2}\.\d{2}\.\d{2}/\d{2}[.:]\d{2})\s+(.+?)(?:,|\s{2,}|$)').firstMatch(raw);
  final parts = [name?.group(1), remi?.group(1)].whereType<String>().map((s) => s.trim()).where((s) => s.isNotEmpty);
  if (parts.isNotEmpty) return parts.join(' · ');
  if (pas != null) return pas.group(1)!.trim();
  return raw.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Any CSV with a header row: finds date, amount (or debit/credit) and
/// description columns by name, in English, Dutch or Greek.
List<ImportedTx> _generic(List<List<String>> rows, String fileName) {
  final h = rows.first.map((x) => x.toLowerCase()).toList();
  int find(List<String> names) => h.indexWhere((c) => names.any((n) => c.contains(n)));
  final iDate = find(['ημερομηνία συναλλαγής', 'ημ/νία', 'ημερομηνία', 'transaction date', 'datum', 'date']);
  final iAmount = find(['ποσό', 'bedrag', 'amount', 'value']);
  final iDebit = find(['χρέωση', 'debit', 'af ']);
  final iCredit = find(['πίστωση', 'credit', 'bij ']);
  final iDesc = find(['περιγραφή', 'αιτιολογία', 'omschrijving', 'description', 'details', 'naam', 'name', 'payee']);
  final iDir = find(['af/bij', 'direction', 'χ/π']);
  if (iDate < 0 || (iAmount < 0 && iDebit < 0 && iCredit < 0)) {
    throw ImportException('Could not find date and amount columns in this file.');
  }
  final account = fileName.toLowerCase().contains('eurobank') || _looksGreek(h) ? 'Eurobank' : 'Bank';
  final out = <ImportedTx>[];
  for (final r in rows.skip(1)) {
    if (r.length <= iDate) continue;
    final date = parseDate(r[iDate]);
    int? amount;
    if (iAmount >= 0 && iAmount < r.length) {
      amount = parseAmount(r[iAmount]);
      if (amount != null && iDir >= 0 && iDir < r.length) {
        final dir = r[iDir].toLowerCase();
        if (dir == 'af' || dir == 'debit' || dir == 'χ') amount = -amount.abs();
      }
    } else {
      final debit = iDebit >= 0 && iDebit < r.length ? parseAmount(r[iDebit]) : null;
      final credit = iCredit >= 0 && iCredit < r.length ? parseAmount(r[iCredit]) : null;
      if (debit != null && debit != 0) amount = -debit.abs();
      if (credit != null && credit != 0) amount = credit.abs();
    }
    if (date == null || amount == null || amount == 0) continue;
    final desc = iDesc >= 0 && iDesc < r.length ? r[iDesc] : '';
    out.add(ImportedTx(
      date: date,
      amountCents: amount,
      description: desc,
      account: account,
      key: 'csv:$account:${r.join('|').hashCode}',
    ));
  }
  return out;
}

/// "1.234,56", "-12.50", "€ 12,00", "12,50-" → cents.
int? parseAmount(String raw) {
  var s = raw.replaceAll(RegExp(r'[^\d,.\-+]'), '');
  if (s.isEmpty) return null;
  var negative = s.startsWith('-') || s.endsWith('-');
  s = s.replaceAll('-', '').replaceAll('+', '');
  final comma = s.lastIndexOf(','), dot = s.lastIndexOf('.');
  if (comma > dot) {
    s = s.replaceAll('.', '').replaceAll(',', '.');
  } else {
    s = s.replaceAll(',', '');
  }
  final v = double.tryParse(s);
  if (v == null) return null;
  final cents = (v * 100).round();
  return negative ? -cents : cents;
}

/// "2026-10-29", "29-10-2026", "29/10/2026", "29.10.2026", "20261029".
DateTime? parseDate(String raw) {
  final s = raw.trim().split(' ').first;
  if (RegExp(r'^\d{8}$').hasMatch(s)) {
    return DateTime.tryParse('${s.substring(0, 4)}-${s.substring(4, 6)}-${s.substring(6)}');
  }
  final iso = DateTime.tryParse(s);
  if (iso != null) return iso;
  final m = RegExp(r'^(\d{1,2})[./-](\d{1,2})[./-](\d{2,4})$').firstMatch(s);
  if (m == null) return null;
  var y = int.parse(m.group(3)!);
  if (y < 100) y += 2000;
  return DateTime(y, int.parse(m.group(2)!), int.parse(m.group(1)!));
}

const _rules = <(String, EntryKind, String)>[
  // Taxes first: they are the most specific.
  ('belastingdienst', EntryKind.tax, 'Income tax'),
  ('gemeente', EntryKind.tax, 'Municipal tax'),
  ('waterschap', EntryKind.tax, 'Municipal tax'),
  ('motorrijtuigenbelasting', EntryKind.tax, 'Road tax'),
  ('ααδε', EntryKind.tax, 'Income tax'),
  ('εφορια', EntryKind.tax, 'Income tax'),
  ('zilveren kruis', EntryKind.tax, 'Health insurance'),
  ('zorgverzekering', EntryKind.tax, 'Health insurance'),
  ('cz groep', EntryKind.tax, 'Health insurance'),
  ('menzis', EntryKind.tax, 'Health insurance'),
  // Subscriptions
  ('netflix', EntryKind.subscription, 'Streaming'),
  ('spotify', EntryKind.subscription, 'Streaming'),
  ('disney', EntryKind.subscription, 'Streaming'),
  ('videoland', EntryKind.subscription, 'Streaming'),
  ('youtube', EntryKind.subscription, 'Streaming'),
  ('anthropic', EntryKind.subscription, 'Software'),
  ('claude.ai', EntryKind.subscription, 'Software'),
  ('openai', EntryKind.subscription, 'Software'),
  ('proton', EntryKind.subscription, 'Software'),
  ('github', EntryKind.subscription, 'Software'),
  ('apple.com/bill', EntryKind.subscription, 'Software'),
  ('google one', EntryKind.subscription, 'Software'),
  ('odido', EntryKind.subscription, 'Phone & internet'),
  ('kpn', EntryKind.subscription, 'Phone & internet'),
  ('vodafone', EntryKind.subscription, 'Phone & internet'),
  ('ziggo', EntryKind.subscription, 'Phone & internet'),
  ('cosmote', EntryKind.subscription, 'Phone & internet'),
  ('basic-fit', EntryKind.subscription, 'Gym'),
  ('basic fit', EntryKind.subscription, 'Gym'),
  // Income
  ('salaris', EntryKind.income, 'Salary'),
  ('salary', EntryKind.income, 'Salary'),
  ('μισθοδοσία', EntryKind.income, 'Salary'),
  ('duo', EntryKind.income, 'Allowance'),
  ('toeslagen', EntryKind.income, 'Allowance'),
  // Spending
  ('albert heijn', EntryKind.expense, 'Groceries'),
  ('jumbo', EntryKind.expense, 'Groceries'),
  ('lidl', EntryKind.expense, 'Groceries'),
  ('aldi', EntryKind.expense, 'Groceries'),
  ('plus', EntryKind.expense, 'Groceries'),
  ('dirk', EntryKind.expense, 'Groceries'),
  ('ah to go', EntryKind.expense, 'Groceries'),
  ('σκλαβενίτης', EntryKind.expense, 'Groceries'),
  ('sklavenitis', EntryKind.expense, 'Groceries'),
  ('ab βασιλόπουλος', EntryKind.expense, 'Groceries'),
  ('thuisbezorgd', EntryKind.expense, 'Eating out'),
  ('uber eats', EntryKind.expense, 'Eating out'),
  ('deliveroo', EntryKind.expense, 'Eating out'),
  ('efood', EntryKind.expense, 'Eating out'),
  ('wolt', EntryKind.expense, 'Eating out'),
  ('mcdonald', EntryKind.expense, 'Eating out'),
  ('starbucks', EntryKind.expense, 'Eating out'),
  ('ns groep', EntryKind.expense, 'Transport'),
  ('ns.nl', EntryKind.expense, 'Transport'),
  ('ov-chipkaart', EntryKind.expense, 'Transport'),
  ('gvb', EntryKind.expense, 'Transport'),
  ('ret', EntryKind.expense, 'Transport'),
  ('uber', EntryKind.expense, 'Transport'),
  ('bolt', EntryKind.expense, 'Transport'),
  ('shell', EntryKind.expense, 'Transport'),
  ('klm', EntryKind.expense, 'Travel'),
  ('transavia', EntryKind.expense, 'Travel'),
  ('aegean', EntryKind.expense, 'Travel'),
  ('ryanair', EntryKind.expense, 'Travel'),
  ('booking.com', EntryKind.expense, 'Travel'),
  ('airbnb', EntryKind.expense, 'Travel'),
  ('bol.com', EntryKind.expense, 'Shopping'),
  ('amazon', EntryKind.expense, 'Shopping'),
  ('coolblue', EntryKind.expense, 'Shopping'),
  ('ikea', EntryKind.expense, 'Shopping'),
  ('action', EntryKind.expense, 'Shopping'),
  ('hema', EntryKind.expense, 'Shopping'),
  ('zara', EntryKind.expense, 'Shopping'),
  ('kruidvat', EntryKind.expense, 'Health'),
  ('etos', EntryKind.expense, 'Health'),
  ('apotheek', EntryKind.expense, 'Health'),
  ('φαρμακείο', EntryKind.expense, 'Health'),
  ('vattenfall', EntryKind.expense, 'Utilities'),
  ('eneco', EntryKind.expense, 'Utilities'),
  ('essent', EntryKind.expense, 'Utilities'),
  ('δεη', EntryKind.expense, 'Utilities'),
  ('pathé', EntryKind.expense, 'Entertainment'),
  ('pathe', EntryKind.expense, 'Entertainment'),
  ('steam', EntryKind.expense, 'Entertainment'),
  ('epic games', EntryKind.expense, 'Entertainment'),
];

/// Lowercases and strips Greek accents and final sigma, so bank exports in
/// capitals ("ΣΚΛΑΒΕΝΙΤΗΣ") match rules written normally ("σκλαβενίτης").
String normalizeText(String s) {
  const from = 'άέήίόύώϊϋΐΰς';
  const to = 'αεηιουωιυιυσ';
  final lower = s.toLowerCase();
  final b = StringBuffer();
  for (final ch in lower.split('')) {
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch);
  }
  return b.toString();
}

/// Matches [needle] at the start of a word, so "action" does not hit "transaction".
bool _hit(String text, String rawNeedle) {
  final needle = normalizeText(rawNeedle);
  var from = 0;
  while (true) {
    final i = text.indexOf(needle, from);
    if (i < 0) return false;
    if (i == 0 || !RegExp(r'[a-z0-9\u0370-\u03ff]').hasMatch(text[i - 1])) {
      final end = i + needle.length;
      if (end == text.length || !RegExp(r'[a-z0-9\u0370-\u03ff]').hasMatch(text[end]) || needle.length > 4) {
        return true;
      }
    }
    from = i + 1;
  }
}

EntryKind guessKind(String description, int signedCents) {
  final d = normalizeText(description);
  if (d.startsWith('top-up') || d.contains('to eur') || d.contains('overboeking eigen rekening')) {
    return EntryKind.transfer;
  }
  for (final (needle, kind, _) in _rules) {
    if (_hit(d, needle)) {
      // A refund from a shop is still income.
      if (signedCents > 0 && kind != EntryKind.income) return EntryKind.income;
      return kind;
    }
  }
  return signedCents > 0 ? EntryKind.income : EntryKind.expense;
}

String guessCategory(String description, EntryKind kind) {
  final d = normalizeText(description);
  if (kind == EntryKind.transfer) return 'Transfer';
  for (final (needle, k, category) in _rules) {
    if (k == kind && _hit(d, needle)) return category;
  }
  return switch (kind) {
    EntryKind.income => _rules.any((r) => _hit(d, r.$1)) ? 'Refund' : 'Other income',
    EntryKind.subscription => 'Other subscription',
    EntryKind.tax => 'Other tax',
    _ => 'Other',
  };
}

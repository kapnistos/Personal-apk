import 'package:intl/intl.dart';

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Adds calendar days. Unlike `add(Duration(days: n))` it keeps the clock time
/// when summer time starts or ends in between.
DateTime addDays(DateTime d, int days) =>
    DateTime(d.year, d.month, d.day + days, d.hour, d.minute, d.second, d.millisecond);

/// Whole calendar days from [a] to [b], ignoring the time of day and summer time.
int daysBetween(DateTime a, DateTime b) =>
    DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

/// Adds calendar months, clamping to the last day (31 Jan + 1 month = 28/29 Feb).
DateTime addMonths(DateTime d, int months) {
  final total = d.year * 12 + (d.month - 1) + months;
  final year = total ~/ 12;
  final month = total % 12 + 1;
  final lastDay = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, d.day > lastDay ? lastDay : d.day, d.hour, d.minute);
}

/// "Today", "Tomorrow", "Yesterday", a weekday within the week, otherwise "12 Mar".
String friendlyDay(DateTime d, {DateTime? now}) {
  final today = dateOnly(now ?? DateTime.now());
  final diff = daysBetween(today, d);
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  if (diff == -1) return 'Yesterday';
  if (diff > 1 && diff < 7) return DateFormat.EEEE().format(d);
  if (d.year == today.year) return DateFormat('d MMM').format(d);
  return DateFormat('d MMM y').format(d);
}

/// Short relative time for "edited" labels.
String relativeTime(DateTime d, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final diff = n.difference(d);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24 && dateOnly(d) == dateOnly(n)) return DateFormat.Hm().format(d);
  return friendlyDay(d, now: n);
}

String money(int cents, String currency, {bool signed = false}) {
  final f = NumberFormat.simpleCurrency(name: currency);
  final text = f.format(cents.abs() / 100);
  if (!signed || cents == 0) return cents < 0 ? '-$text' : text;
  return cents > 0 ? '+$text' : '-$text';
}

String currencySymbol(String currency) => NumberFormat.simpleCurrency(name: currency).currencySymbol;

/// Parses "12", "12.5", "12,50" or "1.234,56" into cents. Returns null if invalid.
int? parseMoney(String input) {
  var s = input.trim().replaceAll(' ', '').replaceAll(RegExp(r'[^\d.,-]'), '');
  if (s.isEmpty) return null;
  final lastComma = s.lastIndexOf(',');
  final lastDot = s.lastIndexOf('.');
  if (','.allMatches(s).length > 1 && lastDot < 0) {
    // "1,234,567": commas only group thousands.
    s = s.replaceAll(',', '');
  } else if ('.'.allMatches(s).length > 1 && lastComma < 0) {
    // "1.234.567": dots only group thousands.
    s = s.replaceAll('.', '');
  } else if (lastComma > lastDot) {
    s = s.replaceAll('.', '').replaceAll(',', '.');
  } else {
    s = s.replaceAll(',', '');
  }
  final v = double.tryParse(s);
  if (v == null) return null;
  return (v * 100).round();
}

/// Cents as text for an input field: "1500" for whole amounts, "12.50" otherwise, so editing keeps the cents.
String moneyInput(int cents) => cents % 100 == 0 ? '${cents ~/ 100}' : (cents / 100).toStringAsFixed(2);

String greeting(DateTime now) {
  final h = now.hour;
  if (h < 5) return 'Good night';
  if (h < 12) return 'Good morning';
  if (h < 18) return 'Good afternoon';
  return 'Good evening';
}

/// The next date of something that repeats: daily, weekdays, weekly, monthly or yearly.
DateTime nextRepeat(DateTime d, String repeat) {
  DateTime plusDays(int n) => DateTime(d.year, d.month, d.day + n, d.hour, d.minute);
  return switch (repeat) {
    'daily' => plusDays(1),
    'weekdays' => plusDays(
      d.weekday == DateTime.friday
          ? 3
          : d.weekday == DateTime.saturday
          ? 2
          : 1,
    ),
    'weekly' => plusDays(7),
    'monthly' => addMonths(d, 1),
    'yearly' => addMonths(d, 12),
    _ => d,
  };
}

const todoRepeatLabels = {
  'none': 'Does not repeat',
  'daily': 'Every day',
  'weekdays': 'Every weekday',
  'weekly': 'Every week',
  'monthly': 'Every month',
  'yearly': 'Every year',
};

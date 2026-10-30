import '../../core/db/database.dart';
import '../../core/format.dart';

/// The hours a contract expects on each weekday, Monday first.
///
/// Kept as one settings value ("8,8,8,8,8,0,0") so no table has to change.
class WorkSchedule {
  const WorkSchedule(this.hours);

  /// Settings key the schedule is stored under.
  static const key = 'job.schedule';

  /// 40 hours, Monday to Friday: what most contracts say, used until the owner sets one.
  static const standard = WorkSchedule([8, 8, 8, 8, 8, 0, 0]);

  final List<double> hours;

  static WorkSchedule parse(String? raw) {
    final parts = (raw ?? '').split(',').map((s) => double.tryParse(s.trim())).toList();
    if (parts.length != 7 || parts.any((h) => h == null || h < 0 || h > 24)) return standard;
    return WorkSchedule([for (final h in parts) h!]);
  }

  /// [weekly] hours spread evenly over [weekdays] (1 = Monday … 7 = Sunday).
  factory WorkSchedule.spread(double weekly, Set<int> weekdays) {
    final each = weekdays.isEmpty ? 0.0 : weekly / weekdays.length;
    return WorkSchedule([for (var d = 1; d <= 7; d++) weekdays.contains(d) ? each : 0]);
  }

  String encode() => hours.map((h) => h == h.roundToDouble() ? h.toStringAsFixed(0) : '$h').join(',');

  double get weekly => hours.fold(0, (a, h) => a + h);

  /// Weekdays (1 = Monday) with hours on them.
  Set<int> get workdays => {
    for (var d = 1; d <= 7; d++)
      if (hours[d - 1] > 0) d,
  };

  /// True when every workday has the same hours, so "40 h over Mon–Fri" says it all.
  bool get even => workdays.map((d) => hours[d - 1]).toSet().length <= 1;

  double forDay(DateTime d) => hours[d.weekday - 1];

  /// "40 h a week, Mon–Fri" or "36 h a week, 4 days".
  String describe() {
    final days = workdays.toList()..sort();
    if (days.isEmpty) return 'No set hours';
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final consecutive = days.last - days.first == days.length - 1;
    final span = days.length == 1
        ? names[days.first - 1]
        : consecutive
        ? '${names[days.first - 1]}–${names[days.last - 1]}'
        : '${days.length} days';
    return '${formatHours(weekly)} h a week, $span';
  }

  @override
  bool operator ==(Object other) => other is WorkSchedule && other.encode() == encode();

  @override
  int get hashCode => encode().hashCode;
}

/// Statuses that stand in for a normal day: they lower what is expected by that day's hours.
const coveredStatuses = {'holiday', 'sick', 'public'};

bool isWorkStatus(String? s) => s == 'work' || s == 'remote';

/// What one day adds to the sums.
class DayHours {
  const DayHours({this.expected = 0, this.done = 0, this.covered = 0});

  /// Hours the contract asks for on this day, after holidays and sick days.
  final double expected;

  /// Hours worked (up to today) or planned (after today).
  final double done;

  /// Contract hours taken care of by a holiday, sick day or public holiday.
  final double covered;

  /// How a day counts:
  /// - worked / from home: the hours entered, or the normal day when none are;
  /// - holiday, sick, public holiday: a normal day that needs no work (expected drops to 0);
  /// - day off on a workday: still expected, so it comes out of the overtime;
  /// - nothing logged: expected only from today on (past days you did not log are left out).
  static DayHours of(String? status, double? hours, double base) => switch (status) {
    'work' || 'remote' => DayHours(expected: base, done: hours ?? base),
    'holiday' || 'sick' || 'public' => DayHours(covered: base),
    'off' => DayHours(expected: base),
    _ => DayHours(expected: base),
  };
}

/// Hours for a stretch of days: done so far, planned, and what is left to do.
class HoursSummary {
  HoursSummary._();

  /// Sums the days from [from] up to but not including [to].
  ///
  /// Days before [today] count only when logged. Today and later count in full,
  /// so the target is the whole period and unlogged workdays are "open".
  factory HoursSummary.of({
    required DateTime from,
    required DateTime to,
    required Map<String, WorkDay> days,
    required WorkSchedule schedule,
    required DateTime today,
  }) {
    final s = HoursSummary._();
    final t = dateOnly(today);
    final n = daysBetween(from, to);
    for (var i = 0; i < n; i++) {
      final day = addDays(dateOnly(from), i);
      final entry = days[AppDatabase.dayKey(day)];
      final base = schedule.forDay(day);
      final past = day.isBefore(t);
      if (entry == null) {
        if (past) {
          if (base > 0) s.unloggedPast++;
          continue;
        }
        s.expected += base;
        if (base > 0) {
          s.openDays++;
          s.openHours += base;
        }
        continue;
      }
      final h = DayHours.of(entry.status, entry.hours, base);
      s.expected += h.expected;
      s.covered += h.covered;
      if (day.isAfter(t)) {
        s.planned += h.done;
      } else {
        s.worked += h.done;
        s.balance += h.done - h.expected;
        s.expectedToDate += h.expected;
      }
    }
    return s;
  }

  /// Contract hours for the period, less holidays, sick days and past days not logged.
  double expected = 0;

  /// Hours worked on logged days up to and including today.
  double worked = 0;

  /// Hours entered on days after today.
  double planned = 0;

  /// Contract hours taken care of by holidays, sick days and public holidays.
  double covered = 0;

  /// Workdays from today on with nothing logged yet.
  int openDays = 0;

  /// Their normal hours together.
  double openHours = 0;

  /// Workdays before today with nothing logged; they count for nothing either way.
  int unloggedPast = 0;

  /// Worked minus expected on logged days up to today: above 0 is overtime, below is owed.
  double balance = 0;

  /// What was expected on the logged days up to today.
  double expectedToDate = 0;

  /// Hours still to find after what is worked and planned (negative: that much over).
  double get remaining => expected - worked - planned;

  /// Hours a day needed on the open days to meet the target; null when there is nothing to make up.
  double? get perOpenDay => remaining > 0.01 && openDays > 0 ? remaining / openDays : null;

  /// Where the period ends if every open day is a normal day.
  double get projected => worked + planned + openHours - expected;
}

/// Start and end of a working day, with a break.
class DayTimes {
  const DayTimes(this.start, this.end, {this.breakMinutes = 0});

  /// Minutes after midnight.
  final int start;
  final int end;
  final int breakMinutes;

  /// Hours between start and end, less the break; an end before the start runs past midnight.
  double get hours {
    var span = end - start;
    if (span <= 0) span += 24 * 60;
    return ((span - breakMinutes).clamp(0, 24 * 60)) / 60;
  }

  static String clock(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

  /// "[09:00-17:30 -30m]": how times ride along at the start of a day's note.
  String get tag => '[${clock(start)}-${clock(end)}${breakMinutes > 0 ? ' -${breakMinutes}m' : ''}]';

  String get label => '${clock(start)}–${clock(end)}${breakMinutes > 0 ? ', $breakMinutes min break' : ''}';

  static final _re = RegExp(r'^\[(\d\d):(\d\d)-(\d\d):(\d\d)(?: -(\d+)m)?\] ?');

  /// The times saved in [note], if any.
  static DayTimes? parse(String note) {
    final m = _re.firstMatch(note);
    if (m == null) return null;
    int g(int i) => int.parse(m.group(i)!);
    return DayTimes(g(1) * 60 + g(2), g(3) * 60 + g(4), breakMinutes: int.tryParse(m.group(5) ?? '') ?? 0);
  }

  /// [note] without the times tag.
  static String strip(String note) => note.replaceFirst(_re, '');

  /// [text] with [times] in front, ready to save as the note.
  static String join(DayTimes? times, String text) =>
      times == null ? text : (text.isEmpty ? times.tag : '${times.tag} $text');
}

double roundQuarter(double h) => (h * 4).round() / 4;

/// 8 → "8", 7.5 → "7.5", 7.25 → "7.25".
String formatHours(double h) {
  final r = (h * 100).round() / 100;
  if (r == r.roundToDouble()) return r.toStringAsFixed(0);
  final s = r.toStringAsFixed(2);
  return s.endsWith('0') ? s.substring(0, s.length - 1) : s;
}

/// "+3.5 h", "−6 h" (a real minus), "0 h".
String signedHours(double h) {
  if (h.abs() < 0.005) return '0 h';
  return '${h > 0 ? '+' : '−'}${formatHours(h.abs())} h';
}

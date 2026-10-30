import 'database.dart';

/// One recurring payment or income that a new install starts with.
class RecurringSeed {
  const RecurringSeed(this.name, this.cents, this.kind, this.category, this.next);
  final String name;
  final int cents;
  final EntryKind kind;
  final String category;
  final DateTime next;
}

/// Your own monthly payments and income, added on first start and restorable from
/// Wallet → Recurring → "Add back my usual list". For example:
///
///   RecurringSeed('Rent', 95000, EntryKind.subscription, 'Rent', DateTime(2026, 11, 1)),
///   RecurringSeed('Salary', 250000, EntryKind.income, 'Salary', DateTime(2026, 11, 25)),
final myRecurring = <RecurringSeed>[];

/// Your own open tasks, added on a fresh install.
const myTasks = <String>[];

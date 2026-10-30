import 'package:flutter/material.dart';

import '../../core/db/database.dart';

class CategoryInfo {
  const CategoryInfo(this.name, this.icon, this.color);
  final String name;
  final IconData icon;
  final Color color;
}

const categoriesByKind = <EntryKind, List<CategoryInfo>>{
  EntryKind.expense: [
    CategoryInfo('Groceries', Icons.shopping_basket_rounded, Color(0xFF2F8F5B)),
    CategoryInfo('Eating out', Icons.restaurant_rounded, Color(0xFFD9822B)),
    CategoryInfo('Transport', Icons.directions_transit_rounded, Color(0xFF3A78C9)),
    CategoryInfo('Housing', Icons.home_rounded, Color(0xFF8A5A44)),
    CategoryInfo('Utilities', Icons.bolt_rounded, Color(0xFFCF9418)),
    CategoryInfo('Shopping', Icons.shopping_bag_rounded, Color(0xFFB5487A)),
    CategoryInfo('Health', Icons.favorite_rounded, Color(0xFFC0563F)),
    CategoryInfo('Entertainment', Icons.local_activity_rounded, Color(0xFF6650AE)),
    CategoryInfo('Travel', Icons.flight_rounded, Color(0xFF2D8C9E)),
    CategoryInfo('Education', Icons.school_rounded, Color(0xFF4F6D8A)),
    CategoryInfo('Other', Icons.more_horiz_rounded, Color(0xFF6F6A60)),
  ],
  EntryKind.subscription: [
    CategoryInfo('Streaming', Icons.play_circle_rounded, Color(0xFFC0392B)),
    CategoryInfo('Software', Icons.apps_rounded, Color(0xFF3A78C9)),
    CategoryInfo('Phone & internet', Icons.wifi_rounded, Color(0xFF2D8C9E)),
    CategoryInfo('Insurance', Icons.shield_rounded, Color(0xFF4F6D8A)),
    CategoryInfo('Rent', Icons.home_rounded, Color(0xFF8A5A44)),
    CategoryInfo('Gym', Icons.fitness_center_rounded, Color(0xFF2F8F5B)),
    CategoryInfo('Other subscription', Icons.autorenew_rounded, Color(0xFF6F6A60)),
  ],
  EntryKind.income: [
    CategoryInfo('Salary', Icons.work_rounded, Color(0xFF2D7A4B)),
    CategoryInfo('Freelance', Icons.handyman_rounded, Color(0xFF1F6F54)),
    CategoryInfo('Allowance', Icons.family_restroom_rounded, Color(0xFF3F8F7A)),
    CategoryInfo('Refund', Icons.undo_rounded, Color(0xFF4C8C5F)),
    CategoryInfo('Gift', Icons.card_giftcard_rounded, Color(0xFF6B9E3F)),
    CategoryInfo('Other income', Icons.add_card_rounded, Color(0xFF5F7F6A)),
  ],
  EntryKind.tax: [
    CategoryInfo('Income tax', Icons.account_balance_rounded, Color(0xFF7A4E9E)),
    CategoryInfo('Municipal tax', Icons.location_city_rounded, Color(0xFF6650AE)),
    CategoryInfo('Road tax', Icons.directions_car_rounded, Color(0xFF5B5BA8)),
    CategoryInfo('Health insurance', Icons.health_and_safety_rounded, Color(0xFF8E5EA8)),
    CategoryInfo('Other tax', Icons.receipt_long_rounded, Color(0xFF6F6A60)),
  ],
  EntryKind.transfer: [CategoryInfo('Transfer', Icons.swap_horiz_rounded, Color(0xFF6F6A60))],
};

CategoryInfo categoryInfo(String name) {
  for (final list in categoriesByKind.values) {
    for (final c in list) {
      if (c.name == name) return c;
    }
  }
  return CategoryInfo(name, Icons.label_rounded, const Color(0xFF6F6A60));
}

extension EntryKindX on EntryKind {
  String get label => switch (this) {
    EntryKind.expense => 'Expense',
    EntryKind.income => 'Income',
    EntryKind.subscription => 'Subscription',
    EntryKind.tax => 'Tax',
    EntryKind.transfer => 'Transfer',
  };

  /// +1 for money in, -1 for money out, 0 for moves between own accounts.
  int get sign => switch (this) {
    EntryKind.income => 1,
    EntryKind.transfer => 0,
    _ => -1,
  };
}

class MonthSummary {
  MonthSummary(List<Entry> entries) {
    for (final e in entries) {
      final s = e.kind.sign;
      if (s > 0) {
        income += e.amountCents;
      } else if (s < 0) {
        out += e.amountCents;
        byKind[e.kind] = (byKind[e.kind] ?? 0) + e.amountCents;
        byCategory[e.category] = (byCategory[e.category] ?? 0) + e.amountCents;
      }
    }
  }

  int income = 0;
  int out = 0;
  final byKind = <EntryKind, int>{};
  final byCategory = <String, int>{};

  int get net => income - out;
}

/// Monthly cost of a subscription, for "per month" totals.
int monthlyCents(Subscription s) => (s.amountCents / (s.periodMonths < 1 ? 1 : s.periodMonths)).round();

String periodLabel(int months) => switch (months) {
  1 => 'Monthly',
  3 => 'Quarterly',
  6 => 'Every 6 months',
  12 => 'Yearly',
  _ => 'Every $months months',
};

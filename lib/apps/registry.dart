import 'package:flutter/material.dart';

import '../core/edition.dart';
import '../core/mini_app.dart';
import '../core/theme.dart';
import 'calendar/calendar_page.dart';
import 'claude/claude_page.dart';
import 'habits/habits_page.dart';
import 'internships/internships_page.dart';
import 'mail/mail_page.dart';
import 'news/news_page.dart';
import 'notes/notes_page.dart';
import 'shopping/shopping_model.dart';
import 'shopping/shopping_page.dart';
import 'spaces/my_spaces.dart';
import 'spaces/space_page.dart';
import 'todo/todo_page.dart';
import 'wallet/wallet_page.dart';
import 'weather/weather_page.dart';

/// Every mini-app on the home screen, in display order.
final miniApps = _allApps.where((a) => personalEdition || !personalOnlyApps.contains(a.id)).toList();

final _allApps = <MiniApp>[
  MiniApp(
    id: 'weather',
    title: 'Weather',
    subtitle: 'Forecast and rain radar',
    icon: Icons.wb_sunny_rounded,
    color: TileColors.weather,
    builder: (_) => const WeatherPage(),
  ),
  MiniApp(
    id: 'calendar',
    title: 'Calendar',
    subtitle: 'Events and reminders',
    icon: Icons.calendar_month_rounded,
    color: const Color(0xFF2D8C9E),
    builder: (_) => const CalendarPage(),
  ),
  MiniApp(
    id: 'todo',
    title: 'To-do',
    subtitle: 'Tasks with reminders',
    icon: Icons.check_circle_rounded,
    color: TileColors.todo,
    builder: (_) => const TodoPage(),
  ),
  MiniApp(
    id: 'notes',
    title: 'Notes',
    subtitle: 'Quick notes',
    icon: Icons.sticky_note_2_rounded,
    color: TileColors.notes,
    builder: (_) => const NotesPage(),
  ),
  MiniApp(
    id: 'wallet',
    title: 'Wallet',
    subtitle: 'Spending, subscriptions, taxes',
    icon: Icons.account_balance_wallet_rounded,
    color: TileColors.finance,
    builder: (_) => const WalletPage(),
  ),
  MiniApp(
    id: 'shopping',
    title: 'Shopping',
    subtitle: 'One list, sorted by the cheapest shop',
    icon: Icons.shopping_basket_rounded,
    color: shoppingColor,
    builder: (_) => const ShoppingPage(),
  ),
  MiniApp(
    id: 'habits',
    title: 'Habits',
    subtitle: 'Daily habits and streaks',
    icon: Icons.local_fire_department_rounded,
    color: habitColor,
    builder: (_) => const HabitsPage(),
  ),
  MiniApp(
    id: 'job',
    title: 'Job',
    subtitle: 'Shifts, work days and days off',
    icon: Icons.work_rounded,
    color: const Color(0xFF1F7A5A),
    builder: (_) => const SpaceLauncher(gid: 'seed-job', fallbackName: 'Job'),
  ),
  MiniApp(
    id: 'lab',
    title: 'Lab',
    subtitle: 'Research plan, meetings, papers',
    icon: Icons.science_rounded,
    color: const Color(0xFF7A5BC0),
    builder: (_) => const SpaceLauncher(gid: 'seed-lab', fallbackName: 'Lab research'),
  ),
  MiniApp(
    id: 'uni',
    title: 'University',
    subtitle: 'Exams, lectures, study plan',
    icon: Icons.school_rounded,
    color: const Color(0xFFC0563F),
    builder: (_) => const SpaceLauncher(gid: 'seed-uni', fallbackName: 'University'),
  ),
  MiniApp(
    id: 'spaces',
    title: 'Spaces',
    subtitle: 'Make your own sections',
    icon: Icons.dashboard_customize_rounded,
    color: const Color(0xFF5F6B7A),
    builder: (_) => const SpacesPage(),
  ),
  MiniApp(
    id: 'internships',
    title: 'Internships',
    subtitle: 'Where to apply and by when',
    icon: Icons.badge_rounded,
    color: internshipColor,
    builder: (_) => const InternshipsPage(),
  ),
  MiniApp(
    id: 'news',
    title: 'News',
    subtitle: 'What you should know today',
    icon: Icons.newspaper_rounded,
    color: const Color(0xFF8A5A44),
    builder: (_) => const NewsPage(),
  ),
  MiniApp(
    id: 'mail',
    title: 'Mail',
    subtitle: 'Gmail, Proton and IMAP',
    icon: Icons.mail_rounded,
    color: TileColors.mail,
    builder: (_) => const MailPage(),
  ),
  MiniApp(
    id: 'claude',
    title: 'Claude',
    subtitle: 'Ask on your plan',
    icon: Icons.auto_awesome_rounded,
    color: TileColors.claude,
    builder: (_) => const ClaudePage(),
  ),
];

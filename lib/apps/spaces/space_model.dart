import 'package:flutter/material.dart';

import 'my_spaces.dart' show mySpaceIcons;

/// Icons a space can use, stored by key.
const spaceIcons = <String, IconData>{
  'work': Icons.work_rounded,
  'science': Icons.science_rounded,
  'school': Icons.school_rounded,
  'folder': Icons.folder_rounded,
  'sport': Icons.fitness_center_rounded,
  'home': Icons.home_rounded,
};

IconData spaceIcon(String key) => spaceIcons[key] ?? mySpaceIcons[key] ?? Icons.folder_rounded;

/// What each kind of space calls its parts, so University reads like a study planner
/// and Job like a work log.
class SpaceWords {
  const SpaceWords({required this.plan, required this.planHint, required this.dates, required this.meetings});
  final String plan;
  final String planHint;
  final String dates;
  final String meetings;

  static SpaceWords of(String icon) => switch (icon) {
        'school' => const SpaceWords(
            plan: 'Study plan',
            planHint: 'Chapters, assignments, revision sessions',
            dates: 'Exams and deadlines',
            meetings: 'Lectures and meetings'),
        'science' => const SpaceWords(
            plan: 'Research plan',
            planHint: 'Experiments, analyses, writing',
            dates: 'Important dates',
            meetings: 'Meetings and lab sessions'),
        'work' => const SpaceWords(
            plan: 'Tasks', planHint: 'Things to do at work', dates: 'Important dates', meetings: 'Shifts and meetings'),
        _ => const SpaceWords(plan: 'Plan', planHint: 'Things to do', dates: 'Important dates', meetings: 'Meetings'),
      };
}

/// Work log statuses, in the order a tap cycles through them.
const workStatuses = ['work', 'remote', 'off', 'holiday', 'sick'];

const workStatusLabels = {
  'work': 'Worked',
  'remote': 'From home',
  'off': 'Day off',
  'holiday': 'Holiday',
  'sick': 'Sick',
};

const workStatusColors = {
  'work': Color(0xFF1F7A5A),
  'remote': Color(0xFF2D8C9E),
  'off': Color(0xFF8A8478),
  'holiday': Color(0xFFCF9418),
  'sick': Color(0xFFC0563F),
};

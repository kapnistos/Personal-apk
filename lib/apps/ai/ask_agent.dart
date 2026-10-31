import 'package:flutter/material.dart';

import 'ai_chat_page.dart';

/// Ready-made requests other apps send to the Hub agent.
abstract final class AgentPrompts {
  static const explainMonth =
      'Explain my month in Wallet: what I spent and earned so far, the biggest categories, how it compares with '
      'last month, how I am doing against my monthly budget, and which recurring payments are still to come. '
      'End with one thing I could do.';
  static const planWeek =
      'Plan my week: read my calendar for the next 7 days and my open tasks with due dates, then give me a short '
      'day by day plan with free slots for the tasks. Suggest moves, and propose them once I agree.';
  static const prioritise =
      'Help me prioritise my to-do list: read my open tasks, then give me the three to do first and why, and what '
      'can wait. Offer to star, reschedule or tick off tasks.';
  static const summariseNotes =
      'Summarise my recent notes: the main themes, anything that looks like a to-do or a date, and what I might '
      'have forgotten. Offer to turn to-dos into tasks.';
}

/// Opens the Hub agent in a new conversation and sends [prompt] straight away.
///
/// The way any app hands a question to the agent, e.g. Wallet's "Explain my month".
Future<void> openAgentWith(BuildContext context, String prompt) => Navigator.of(
  context,
  rootNavigator: true,
).push(MaterialPageRoute(builder: (_) => AiChatPage(agent: true, initialText: prompt)));

/// A small sparkle button for an app bar that asks the agent [prompt]; [label] is its tooltip.
class AskAgentButton extends StatelessWidget {
  const AskAgentButton({super.key, required this.label, required this.prompt});
  final String label;
  final String prompt;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: label,
    icon: const Icon(Icons.auto_awesome_outlined),
    onPressed: () => openAgentWith(context, prompt),
  );
}

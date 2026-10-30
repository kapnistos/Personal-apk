import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Hands work to Claude through the official Claude apps, so it runs on the
/// user's own Claude plan. No API key is used anywhere.
class ClaudeBridge {
  /// Longer prompts are passed by clipboard only, since URLs have size limits.
  static const maxUrlPrompt = 3500;

  static Uri newChatUri([String prompt = '']) =>
      Uri.https('claude.ai', '/new', prompt.isEmpty || prompt.length > maxUrlPrompt ? null : {'q': prompt});

  /// Opens Claude. On Windows the desktop app is tried first.
  static Future<bool> open([String prompt = '']) async {
    if (!kIsWeb && Platform.isWindows) {
      try {
        if (await launchUrl(Uri.parse('claude://'), mode: LaunchMode.externalApplication)) {
          return true;
        }
      } catch (_) {
        // Desktop app not installed; fall through to the web.
      }
    }
    // On Android, claude.ai links open in the Claude app when it is installed.
    return launchUrl(newChatUri(prompt), mode: LaunchMode.externalApplication);
  }

  /// Copies [prompt] and opens a new Claude chat with it.
  static Future<void> ask(BuildContext context, String prompt) async {
    final messenger = ScaffoldMessenger.of(context);
    final text = prompt.trim();
    if (text.isNotEmpty) await Clipboard.setData(ClipboardData(text: text));
    final opened = await open(text);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            !opened
                ? 'Could not open Claude. The prompt is on your clipboard.'
                : text.isEmpty
                ? 'Opening Claude'
                : 'Prompt copied. Paste it in Claude if it is not filled in.',
          ),
        ),
      );
  }
}

/// The clipboard text, when it looks like Claude's answer rather than the prompt we copied.
String? claudeAnswerOnClipboard(String? clip, String prompt) {
  final t = clip?.trim() ?? '';
  if (t.isEmpty || t == prompt.trim()) return null;
  return t;
}

/// Hands a prompt to Claude and, when the user comes back to Hub with an answer
/// on the clipboard, offers to use it.
mixin ClaudeAnswerWatcher<T extends StatefulWidget> on State<T>, WidgetsBindingObserver {
  String? _sentPrompt;

  /// What to tell the user about the answer, e.g. "Use Claude's prices?".
  String get answerQuestion => "Use Claude's answer from your clipboard?";

  /// Called with the copied answer after the user taps Use.
  Future<void> onClaudeAnswer(String text);

  Future<void> askClaude(String prompt) async {
    _sentPrompt = prompt.trim();
    WidgetsBinding.instance.removeObserver(this);
    WidgetsBinding.instance.addObserver(this);
    await ClaudeBridge.ask(context, prompt);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _sentPrompt != null) checkClipboardForAnswer();
  }

  /// Looks at the clipboard once and offers the answer if there is one.
  Future<void> checkClipboardForAnswer() async {
    final prompt = _sentPrompt;
    if (prompt == null) return;
    final clip = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    final answer = claudeAnswerOnClipboard(clip, prompt);
    if (answer == null || !mounted) return;
    _sentPrompt = null;
    WidgetsBinding.instance.removeObserver(this);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 12),
          content: Text(answerQuestion),
          action: SnackBarAction(label: 'Use', onPressed: () => onClaudeAnswer(answer)),
        ),
      );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

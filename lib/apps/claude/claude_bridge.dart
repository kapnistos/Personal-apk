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

  static Uri newChatUri([String prompt = '']) => Uri.https(
        'claude.ai',
        '/new',
        prompt.isEmpty || prompt.length > maxUrlPrompt ? null : {'q': prompt},
      );

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
      ..showSnackBar(SnackBar(
        content: Text(!opened
            ? 'Could not open Claude. The prompt is on your clipboard.'
            : text.isEmpty
                ? 'Opening Claude'
                : 'Prompt copied. Paste it in Claude if it is not filled in.'),
      ));
  }
}

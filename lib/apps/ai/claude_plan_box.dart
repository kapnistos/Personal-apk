import 'package:flutter/material.dart';

import '../../core/settings.dart';
import '../../core/theme.dart';
import 'ai_service.dart';
import 'ai_widgets.dart';

/// How the Claude Code option works, with a button that asks a tiny question.
/// Shown in AI settings when Claude Code is chosen.
class ClaudePlanBox extends StatefulWidget {
  const ClaudePlanBox({super.key});

  @override
  State<ClaudePlanBox> createState() => _ClaudePlanBoxState();
}

class _ClaudePlanBoxState extends State<ClaudePlanBox> {
  bool _testing = false;
  bool _ok = false;
  String? _status;

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _status = null;
    });
    final ai = AiSetup(context.settings);
    try {
      final r = await ai.ask(const [AiMessage('user', 'Say ok.')], system: 'Answer with one word.');
      _ok = true;
      _status = 'Works. ${ai.modelName} answered: ${r.text}';
    } on AiException catch (e) {
      _ok = false;
      _status = e.message;
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Runs Claude Code on this computer, or on the laptop running Hub in Server mode. Sign in by running '
          '`claude` there once. If it cannot be reached, Hub opens the Claude app instead.',
          style: TextStyle(color: p.muted, fontSize: 13.5, height: 1.4),
        ),
        const SizedBox(height: 10),
        AiPill(label: 'Test', icon: Icons.bolt_rounded, busy: _testing, onTap: _test),
        if (_status != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_status!, style: TextStyle(color: _ok ? p.positive : p.danger, height: 1.4)),
          ),
      ],
    );
  }
}

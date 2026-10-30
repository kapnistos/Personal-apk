import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';

/// The AI app's colour. Only its circles carry it.
const aiColor = Color(0xFF4D6BFE);

/// A pill button: filled ink for the main action, neutral grey otherwise. At least 44 high.
class AiPill extends StatelessWidget {
  const AiPill({
    super.key,
    required this.label,
    required this.onTap,
    this.filled = false,
    this.icon,
    this.busy = false,
  });
  final String label;
  final VoidCallback? onTap;
  final bool filled;
  final IconData? icon;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final fg = filled ? p.background : p.ink;
    final enabled = onTap != null && !busy;
    return Semantics(
      button: true,
      enabled: enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: Pressable(
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 140),
            opacity: enabled || busy ? 1 : 0.45,
            child: Container(
              constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: ShapeDecoration(color: filled ? p.ink : p.raised, shape: const StadiumBorder()),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (busy)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        '…',
                        style: TextStyle(color: fg, fontWeight: FontWeight.w700),
                      ),
                    )
                  else if (icon != null) ...[
                    Icon(icon, size: 18, color: fg),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: fg, fontSize: 14.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A neutral grey circle with one icon, 44 across.
class AiRoundButton extends StatelessWidget {
  const AiRoundButton({super.key, required this.icon, required this.tooltip, required this.onTap, this.filled = false});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  /// Ink circle (the send button) instead of grey.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: onTap != null,
        child: GestureDetector(
          onTap: onTap,
          child: Pressable(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 140),
              opacity: onTap == null ? 0.45 : 1,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: filled ? p.ink : p.raised, shape: BoxShape.circle),
                child: Icon(icon, color: filled ? p.background : p.ink, size: 21),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One choice in a list: a title, a muted line and a round check on the right.
class AiCheckRow extends StatelessWidget {
  const AiCheckRow({super.key, required this.title, this.subtitle, required this.selected, required this.onTap});
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Pressable(
          scale: 0.98,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        if (subtitle != null && subtitle!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(subtitle!, style: TextStyle(color: p.muted, fontSize: 13.5, height: 1.35)),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected ? p.ink : Colors.transparent,
                      border: Border.all(color: selected ? p.ink : p.muted, width: 1.6),
                    ),
                    child: selected ? Icon(Icons.check_rounded, size: 16, color: p.background) : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A small muted heading inside the settings sheet.
class AiLabel extends StatelessWidget {
  const AiLabel(this.text, {super.key, this.top = 20});
  final String text;
  final double top;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(top: top, bottom: 4),
    child: Text(
      text,
      style: TextStyle(color: Palette.of(context).muted, fontSize: 13, fontWeight: FontWeight.w600),
    ),
  );
}

/// A model's answer as styled text: **bold**, *italic*, `code`, headings, lists and code blocks become
/// type instead of stray symbols. One span tree, so the whole answer stays selectable and copyable.
TextSpan aiMarkdown(String text, {required TextStyle base, required Color codeBackground}) {
  final mono = base.copyWith(fontFamily: 'monospace', fontSize: (base.fontSize ?? 16) * 0.88);
  final spans = <InlineSpan>[];
  final lines = text.replaceAll('\r\n', '\n').split('\n');
  var inCode = false;
  var first = true;
  void newline() {
    if (!first) spans.add(const TextSpan(text: '\n'));
    first = false;
  }

  for (final raw in lines) {
    final line = raw.trimRight();
    if (line.trimLeft().startsWith('```')) {
      inCode = !inCode;
      continue;
    }
    if (inCode) {
      newline();
      spans.add(
        TextSpan(
          text: line,
          style: mono.copyWith(backgroundColor: codeBackground),
        ),
      );
      continue;
    }
    newline();
    final heading = RegExp(r'^\s{0,3}#{1,6}\s+(.*)$').firstMatch(line);
    if (heading != null) {
      spans.add(
        TextSpan(
          children: _inline(heading[1]!, base, mono, codeBackground),
          style: base.copyWith(fontWeight: FontWeight.w700),
        ),
      );
      continue;
    }
    final bullet = RegExp(r'^(\s*)[-*•]\s+(.*)$').firstMatch(line);
    if (bullet != null) {
      final indent = bullet[1]!.length >= 2 ? '      ' : '';
      spans.add(TextSpan(text: '$indent•  ', style: base));
      spans.addAll(_inline(bullet[2]!, base, mono, codeBackground));
      continue;
    }
    final numbered = RegExp(r'^\s*(\d{1,3})[.)]\s+(.*)$').firstMatch(line);
    if (numbered != null) {
      spans.add(
        TextSpan(
          text: '${numbered[1]}.  ',
          style: base.copyWith(fontWeight: FontWeight.w600),
        ),
      );
      spans.addAll(_inline(numbered[2]!, base, mono, codeBackground));
      continue;
    }
    if (RegExp(r'^\s*(-{3,}|\*{3,}|_{3,})\s*$').hasMatch(line)) continue;
    spans.addAll(_inline(line.replaceFirst(RegExp(r'^\s*>\s?'), ''), base, mono, codeBackground));
  }
  return TextSpan(style: base, children: spans);
}

final _inlinePattern = RegExp(
  r'\*\*(.+?)\*\*|__(.+?)__|`([^`]+)`|(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?!\w)|(?<!\w)_(?!\s)(.+?)(?<!\s)_(?!\w)',
);

List<InlineSpan> _inline(String s, TextStyle base, TextStyle mono, Color codeBackground) {
  final out = <InlineSpan>[];
  var at = 0;
  for (final m in _inlinePattern.allMatches(s)) {
    if (m.start > at) out.add(TextSpan(text: s.substring(at, m.start)));
    if (m[1] != null || m[2] != null) {
      out.add(
        TextSpan(
          text: m[1] ?? m[2],
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      );
    } else if (m[3] != null) {
      out.add(
        TextSpan(
          text: m[3],
          style: mono.copyWith(backgroundColor: codeBackground),
        ),
      );
    } else {
      out.add(
        TextSpan(
          text: m[4] ?? m[5],
          style: const TextStyle(fontStyle: FontStyle.italic),
        ),
      );
    }
    at = m.end;
  }
  if (at < s.length) out.add(TextSpan(text: s.substring(at)));
  return out;
}

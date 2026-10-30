import 'package:flutter/material.dart';

import 'theme.dart';

/// Caps content width so pages read well on a wide Windows window.
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child, this.maxWidth = 720});
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      );
}

/// A card with a small heading, used to group content on a page.
class Section extends StatelessWidget {
  const Section({super.key, required this.title, required this.child, this.trailing});
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, 14, trailing == null ? 16 : 6, 6),
            child: Row(children: [
              Expanded(child: SectionLabel(title)),
              ?trailing,
            ]),
          ),
          child,
        ],
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Palette.of(context).muted),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.message, this.action});
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(color: p.raised, shape: BoxShape.circle),
                child: Icon(icon, size: 30, color: p.muted),
              ),
              const SizedBox(height: 16),
              Text(title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text(message, style: TextStyle(color: p.muted, height: 1.4), textAlign: TextAlign.center),
              if (action != null) ...[const SizedBox(height: 18), action!],
            ],
          ),
        ),
      ),
    );
  }
}

/// A flat circle with an icon, in a mini-app's colour.
class AppGlyph extends StatelessWidget {
  const AppGlyph({super.key, required this.icon, required this.color, this.size = 48});
  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: Colors.white, size: size * 0.48),
    );
  }
}

/// A large money figure with the cents set smaller, the way bank apps show a balance.
class BigAmount extends StatelessWidget {
  const BigAmount(this.text, {super.key, this.size = 40, this.color});
  final String text;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Palette.of(context).ink;
    final m = RegExp(r'^(.*?)([.,]\d{2})(\D*)$').firstMatch(text);
    final style = TextStyle(
      fontSize: size,
      fontWeight: FontWeight.w700,
      letterSpacing: -size * 0.03,
      color: c,
      height: 1.1,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    if (m == null) return Text(text, style: style, maxLines: 1);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: m[1]),
          TextSpan(text: '${m[2]}${m[3]}', style: style.copyWith(fontSize: size * 0.6, letterSpacing: 0)),
        ],
      ),
      style: style,
      maxLines: 1,
    );
  }
}

void showUndo(BuildContext context, String message, VoidCallback onUndo) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      action: SnackBarAction(label: 'Undo', onPressed: onUndo),
    ));
}

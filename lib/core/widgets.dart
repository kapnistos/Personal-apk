import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'settings.dart';
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
  const Section({super.key, required this.title, required this.child, this.trailing, this.onTap});
  final String title;
  final Widget child;
  final Widget? trailing;

  /// Opens what the section is about when the card itself is tapped, anywhere its rows do not take the tap.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        // Without a tap the card is not a stop for the keyboard either.
        canRequestFocus: onTap != null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(16, 14, trailing == null ? 16 : 6, 6),
              child: Row(
                children: [
                  Expanded(child: SectionLabel(title)),
                  ?trailing,
                ],
              ),
            ),
            child,
          ],
        ),
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
    // Scrolls when the space is short (small phones, big text, keyboard open) instead of overflowing.
    final content = Center(
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
              Text(
                message,
                style: TextStyle(color: p.muted, height: 1.4),
                textAlign: TextAlign.center,
              ),
              if (action != null) ...[const SizedBox(height: 18), action!],
            ],
          ),
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, box) => !box.maxHeight.isFinite
          ? content
          : SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: box.maxHeight),
                child: content,
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
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
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
          TextSpan(
            text: '${m[2]}${m[3]}',
            style: style.copyWith(fontSize: size * 0.6, letterSpacing: 0),
          ),
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
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(label: 'Undo', onPressed: onUndo),
      ),
    );
}

/// Rebuilds its builder only when the picked setting changes, not on every settings write.
class SettingSelector<T> extends StatefulWidget {
  const SettingSelector({super.key, required this.select, required this.builder});
  final T Function(AppSettings s) select;
  final Widget Function(BuildContext context, T value) builder;

  @override
  State<SettingSelector<T>> createState() => _SettingSelectorState<T>();
}

class _SettingSelectorState<T> extends State<SettingSelector<T>> {
  AppSettings? _settings;
  late T _value;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = context.settings;
    if (s == _settings) return;
    _settings?.removeListener(_changed);
    _settings = s..addListener(_changed);
    _value = widget.select(s);
  }

  @override
  void didUpdateWidget(SettingSelector<T> old) {
    super.didUpdateWidget(old);
    final s = _settings;
    if (s != null) _value = widget.select(s);
  }

  void _changed() {
    if (!mounted) return;
    final v = widget.select(_settings!);
    if (v != _value) setState(() => _value = v);
  }

  @override
  void dispose() {
    _settings?.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _value);
}

/// A row of colour dots; the chosen one gets a ring.
class ColorDots extends StatelessWidget {
  const ColorDots({super.key, required this.colors, required this.selected, required this.onSelected, this.labels});
  final List<Color> colors;
  final int selected;
  final ValueChanged<int> onSelected;
  final List<String>? labels;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final (i, c) in colors.indexed)
          Tooltip(
            message: labels?[i] ?? '',
            child: Semantics(
              button: true,
              selected: i == selected,
              label: labels?[i],
              child: GestureDetector(
                onTap: () => onSelected(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 40,
                  height: 40,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: i == selected ? p.ink : Colors.transparent, width: 2),
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                    child: i == selected ? const Icon(Icons.check_rounded, size: 18, color: Colors.white) : null,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Grey placeholder lines shown while content loads. They stay invisible for the first
/// 250 ms, so a quick load never flashes, then fade in and breathe gently.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.lines = 3, this.padding = const EdgeInsets.all(16), this.leading = true});
  final int lines;
  final EdgeInsets padding;

  /// Draws a circle before each line, like a list of rows with avatars.
  final bool leading;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
  bool _shown = false;
  Timer? _wait;

  @override
  void initState() {
    super.initState();
    _wait = Timer(const Duration(milliseconds: 250), () {
      setState(() => _shown = true);
      _pulse.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _wait?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    Widget bar(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(color: p.raised, borderRadius: BorderRadius.circular(height / 2)),
    );
    return Semantics(
      label: 'Loading',
      child: AnimatedOpacity(
        opacity: _shown ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: FadeTransition(
          opacity: Tween(begin: 1.0, end: 0.55).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
          child: Padding(
            padding: widget.padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < widget.lines; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        if (widget.leading) ...[
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(color: p.raised, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 14),
                        ],
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, c) => Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                bar(c.maxWidth * (i.isEven ? 0.7 : 0.55), 12),
                                const SizedBox(height: 8),
                                bar(c.maxWidth * (i.isEven ? 0.4 : 0.5), 10),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A pill-shaped switch between a few options; the chosen one sits on a solid pill that slides across.
class PillToggle<T> extends StatelessWidget {
  const PillToggle({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.dense = false,
  });
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final n = options.length;
    final index = options.indexWhere((o) => o.$1 == value);
    const duration = Duration(milliseconds: 200);
    return IntrinsicWidth(
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: ShapeDecoration(color: p.raised, shape: const StadiumBorder()),
        child: Stack(
          children: [
            if (index >= 0)
              Positioned.fill(
                child: AnimatedAlign(
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  alignment: Alignment(n == 1 ? 0 : -1 + 2 * index / (n - 1), 0),
                  child: FractionallySizedBox(
                    widthFactor: 1 / n,
                    heightFactor: 1,
                    child: DecoratedBox(
                      decoration: ShapeDecoration(color: p.ink, shape: const StadiumBorder()),
                    ),
                  ),
                ),
              ),
            Row(
              children: [
                for (final (i, (v, label)) in options.indexed)
                  Expanded(
                    child: Semantics(
                      button: true,
                      selected: i == index,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          if (v == value) return;
                          HapticFeedback.selectionClick();
                          onChanged(v);
                        },
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minHeight: dense ? 34 : 40, minWidth: dense ? 52 : 64),
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: dense ? 12 : 16, vertical: 6),
                            child: Center(
                              child: AnimatedDefaultTextStyle(
                                duration: duration,
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: dense ? 14 : 14.5,
                                  fontWeight: FontWeight.w600,
                                  color: i == index ? p.background : p.ink,
                                ),
                                child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Shrinks its child to 95% while a finger is down, so a tap feels physical without a ripple.
/// It only listens to the pointer, so the child's own gestures (tap, hold) still win as before.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.scale = 0.95});
  final Widget child;
  final double scale;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (mounted && _down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => _set(true),
    onPointerUp: (_) => _set(false),
    onPointerCancel: (_) => _set(false),
    child: AnimatedScale(
      scale: _down ? widget.scale : 1,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      child: widget.child,
    ),
  );
}

/// A round app button: a coloured circle with a white glyph, a label under it and an optional count badge.
/// The whole box, padding included, takes the tap, so there are no dead gaps between buttons.
class AppCircle extends StatelessWidget {
  const AppCircle({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
    this.badge = 0,
    this.dimmed = false,
    this.size = 52,
  });
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  final int badge;
  final bool dimmed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      button: true,
      label: badge > 0 ? '$label, $badge' : label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Pressable(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(2, 8, 2, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: size + 8,
                  height: size,
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      Opacity(
                        opacity: dimmed ? 0.45 : 1,
                        child: AppGlyph(icon: icon, color: color, size: size),
                      ),
                      if (badge > 0)
                        Positioned(
                          top: -3,
                          right: -1,
                          child: Container(
                            constraints: const BoxConstraints(minWidth: 21),
                            height: 21,
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: p.danger,
                              borderRadius: BorderRadius.circular(11),
                              // A ring in the page colour lifts the badge off the circle.
                              border: Border.all(color: p.background, width: 2),
                            ),
                            child: Text(
                              badge > 99 ? '99+' : '$badge',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                height: 1,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.1,
                    color: dimmed ? p.muted : p.ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

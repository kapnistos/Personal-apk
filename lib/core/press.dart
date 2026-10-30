import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// Shrinks its child to 0.95 while a finger is down, over 140 ms. Purely visual: it never takes the tap,
/// so it can wrap anything that already handles taps (a ListTile, an InkWell, a button).
class Press extends StatefulWidget {
  const Press({super.key, required this.child, this.enabled = true});
  final Widget child;
  final bool enabled;

  @override
  State<Press> createState() => _PressState();
}

class _PressState extends State<Press> {
  bool _down = false;
  Offset _start = Offset.zero;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return Listener(
      onPointerDown: (e) {
        _start = e.position;
        _set(true);
      },
      // A drag is a scroll, not a press.
      onPointerMove: (e) {
        if ((e.position - _start).distance > 12) _set(false);
      },
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down ? 0.95 : 1,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// A 44 px round icon button on the raised surface, as in the page headers.
class RoundButton extends StatelessWidget {
  const RoundButton({super.key, required this.icon, required this.onPressed, this.tooltip, this.filled = false});
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  /// Ink-filled, for the one prominent action.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Press(
      enabled: onPressed != null,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: 22),
        style: IconButton.styleFrom(
          backgroundColor: filled ? p.ink : p.raised,
          foregroundColor: filled ? p.background : p.ink,
          fixedSize: const Size.square(44),
          minimumSize: const Size.square(44),
          padding: EdgeInsets.zero,
          shape: const CircleBorder(),
        ),
      ),
    );
  }
}

/// The page header: round icon buttons on the raised surface, a bold title. Pushed pages get a round back
/// button and a centred title; top-level pages a big title on the left.
class HubBar extends StatelessWidget implements PreferredSizeWidget {
  const HubBar({
    super.key,
    this.title,
    this.actions,
    this.leading,
    this.titleSpacing,
    this.backgroundColor,
    this.centerTitle,
    this.automaticallyImplyLeading = true,
    this.bottom,
  });
  final Widget? title;
  final List<Widget>? actions;
  final Widget? leading;
  final double? titleSpacing;
  final Color? backgroundColor;
  final bool? centerTitle;
  final bool automaticallyImplyLeading;
  final PreferredSizeWidget? bottom;

  static const height = 64.0;

  @override
  Size get preferredSize => Size.fromHeight(height + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = Palette.of(context);
    final route = ModalRoute.of(context);
    final canPop = automaticallyImplyLeading && (route?.impliesAppBarDismissal ?? false);
    final lead =
        leading ??
        (canPop ? (route is PageRoute && route.fullscreenDialog ? const CloseButton() : const BackButton()) : null);
    final pushed = lead != null;
    final buttonStyle = IconButton.styleFrom(
      backgroundColor: p.raised,
      foregroundColor: p.ink,
      fixedSize: const Size.square(44),
      minimumSize: const Size.square(44),
      padding: EdgeInsets.zero,
      shape: const CircleBorder(),
      iconSize: 22,
    );
    return Theme(
      data: theme.copyWith(iconButtonTheme: IconButtonThemeData(style: buttonStyle)),
      child: AppBar(
        toolbarHeight: height,
        backgroundColor: backgroundColor,
        automaticallyImplyLeading: false,
        leadingWidth: pushed ? 64 : null,
        leading: pushed
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Press(child: lead),
                ),
              )
            : null,
        centerTitle: centerTitle ?? pushed,
        titleSpacing: titleSpacing ?? (pushed ? 8 : 20),
        title: title == null
            ? null
            : DefaultTextStyle.merge(
                style: pushed
                    ? const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.4)
                    : const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.9),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                child: title!,
              ),
        actionsPadding: const EdgeInsets.only(right: 12),
        bottom: bottom,
        actions: [
          for (final a in actions ?? const <Widget>[])
            // Spacers from before the round buttons are left out; the bar sets its own spacing.
            if (!(a is SizedBox && a.child == null))
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Press(child: a),
              ),
        ],
      ),
    );
  }
}

/// Pill tabs: the chosen one filled with the ink colour and inverse text, the others on the raised surface.
class PillTabs<T> extends StatelessWidget {
  const PillTabs({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.padding = EdgeInsets.zero,
  });
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: padding,
        child: Row(
          children: [
            for (final (i, (v, label)) in options.indexed) ...[
              if (i > 0) const SizedBox(width: 8),
              Semantics(
                button: true,
                selected: v == value,
                child: Press(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (v == value) return;
                      HapticFeedback.selectionClick();
                      onChanged(v);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      constraints: const BoxConstraints(minHeight: 44),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      alignment: Alignment.center,
                      decoration: ShapeDecoration(color: v == value ? p.ink : p.raised, shape: const StadiumBorder()),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: v == value ? p.background : p.ink,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Rows grouped in one rounded card, split by thin lines.
class GroupCard extends StatelessWidget {
  const GroupCard({super.key, required this.children, this.indent = 16, this.color});
  final List<Widget> children;

  /// Where the dividers start, so they line up with the row text after a leading circle.
  final double indent;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Material(
      color: color ?? p.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, c) in children.indexed) ...[
            if (i > 0) Divider(height: 1, thickness: 0.6, indent: indent, color: p.line),
            c,
          ],
        ],
      ),
    );
  }
}

/// A muted, sentence-case label above a group.
class GroupLabel extends StatelessWidget {
  const GroupLabel(this.text, {super.key, this.trailing, this.padding = const EdgeInsets.fromLTRB(4, 18, 4, 8)});
  final String text;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Palette.of(context).muted),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

/// Heavy, tight numerals for key numbers.
TextStyle numeralStyle(double size, {Color? color}) => TextStyle(
  fontSize: size,
  fontWeight: FontWeight.w800,
  letterSpacing: -size * 0.04,
  height: 1.05,
  color: color,
  fontFeatures: const [FontFeature.tabularFigures()],
);

/// A muted label with its rows in one rounded card below it. Pass [children] to split rows with thin lines.
class GroupSection extends StatelessWidget {
  const GroupSection({super.key, required this.title, this.child, this.children, this.trailing, this.indent = 68});
  final String title;
  final Widget? child;
  final List<Widget>? children;
  final Widget? trailing;
  final double indent;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(4, 4, trailing == null ? 4 : 0, 8),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: trailing == null ? 0 : 44),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.muted),
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        ),
        if (children != null)
          GroupCard(indent: indent, children: children!)
        else
          Material(
            color: p.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            clipBehavior: Clip.antiAlias,
            child: child,
          ),
      ],
    );
  }
}

/// A neutral round icon at the start of a settings row.
class RowIcon extends StatelessWidget {
  const RowIcon(this.icon, {super.key, this.color});
  final IconData icon;

  /// A colour circle instead of the neutral one, for items that carry a colour.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(color: color ?? p.raised, shape: BoxShape.circle),
      child: Icon(icon, size: 20, color: color == null ? p.ink : Colors.white),
    );
  }
}

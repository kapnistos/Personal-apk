import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../core/theme.dart';
import 'weather_service.dart';

/// Colours for each rain band. Heavier rain is darker on a light page and brighter on a dark one, so the
/// strongest bars always stand out most, and even the lightest bars keep about 3:1 contrast with the card.
class RainColors {
  const RainColors(this.light, this.moderate, this.heavy);
  final Color light;
  final Color moderate;
  final Color heavy;

  static const onLight = RainColors(Color(0xFF5B95E0), Color(0xFF2F63B8), Color(0xFF16306E));
  static const onDark = RainColors(Color(0xFF3F6FB5), Color(0xFF6A9EF0), Color(0xFFB8D3FF));

  static RainColors of(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? onDark : onLight;

  Color forLevel(RainLevel l) => switch (l) {
    RainLevel.none => Colors.transparent,
    RainLevel.light => light,
    RainLevel.moderate => moderate,
    RainLevel.heavy => heavy,
  };
}

/// Where a rain amount sits on the chart, from 0 (baseline) to 1 (top). Each band gets a third of the
/// height and a log scale inside it, so 0.3 mm/h drizzle is clearly visible and a 20 mm/h downpour still fits.
double rainHeight(double mm) {
  if (mm < RainLevel.wet) return 0;
  double band(double v, double lo, double hi) => (math.log(v / lo) / math.log(hi / lo)).clamp(0.0, 1.0);
  if (mm < 1) return 0.04 + (1 / 3 - 0.04) * band(mm, RainLevel.wet, 1);
  if (mm < 5) return 1 / 3 + band(mm, 1, 5) / 3;
  return 2 / 3 + band(mm, 5, 25) / 3;
}

/// The rain chart: one bar per forecast step, placed by time, with Light/Moderate/Heavy bands on the right.
/// Touch or drag across it to read a step.
class RainChart extends StatefulWidget {
  const RainChart({super.key, required this.nowcast, this.onSelect});
  final Nowcast nowcast;

  /// Called with the step under the finger, and with null when the finger lifts.
  final ValueChanged<RainPoint?>? onSelect;

  @override
  State<RainChart> createState() => _RainChartState();
}

class _RainChartState extends State<RainChart> {
  int? _selected;

  static const _labelWidth = 70.0;

  void _pick(Offset local, double width) {
    final n = widget.nowcast;
    if (n.points.isEmpty) return;
    final plot = width - _labelWidth;
    final start = n.points.first.time;
    final span = n.end.difference(start).inSeconds;
    final t = start.add(Duration(seconds: (span * (local.dx / plot).clamp(0.0, 0.9999)).round()));
    final i = n.points.lastIndexWhere((p) => !p.time.isAfter(t));
    final index = i < 0 ? 0 : i;
    if (index != _selected) {
      setState(() => _selected = index);
      widget.onSelect?.call(n.points[index]);
    }
  }

  void _clear() {
    if (_selected == null) return;
    setState(() => _selected = null);
    widget.onSelect?.call(null);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final base = DefaultTextStyle.of(context).style;
    return LayoutBuilder(
      builder: (context, box) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => _pick(d.localPosition, box.maxWidth),
        onTapUp: (_) => _clear(),
        onTapCancel: _clear,
        onHorizontalDragStart: (d) => _pick(d.localPosition, box.maxWidth),
        onHorizontalDragUpdate: (d) => _pick(d.localPosition, box.maxWidth),
        onHorizontalDragEnd: (_) => _clear(),
        onHorizontalDragCancel: _clear,
        child: CustomPaint(
          size: Size(box.maxWidth, 136),
          painter: _RainPainter(
            nowcast: widget.nowcast,
            selected: _selected,
            colors: RainColors.of(context),
            line: p.line,
            muted: p.muted,
            ink: p.ink,
            labelStyle: base.copyWith(fontSize: 11.5, color: p.muted, height: 1.1),
            labelWidth: _labelWidth,
          ),
        ),
      ),
    );
  }
}

class _RainPainter extends CustomPainter {
  _RainPainter({
    required this.nowcast,
    required this.selected,
    required this.colors,
    required this.line,
    required this.muted,
    required this.ink,
    required this.labelStyle,
    required this.labelWidth,
  });

  final Nowcast nowcast;
  final int? selected;
  final RainColors colors;
  final Color line;
  final Color muted;
  final Color ink;
  final TextStyle labelStyle;
  final double labelWidth;

  static const _axis = 24.0;

  TextPainter _text(String s, {TextStyle? style}) => TextPainter(
    text: TextSpan(text: s, style: style ?? labelStyle),
    textDirection: TextDirection.ltr,
  )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    final pts = nowcast.points;
    final plotW = size.width - labelWidth;
    final plotH = size.height - _axis;
    if (pts.isEmpty || plotW <= 0) return;

    final start = pts.first.time;
    final span = nowcast.end.difference(start).inSeconds.toDouble();
    double x(DateTime t) => (t.difference(start).inSeconds / span * plotW).clamp(0.0, plotW);
    double y(double fraction) => plotH - fraction * plotH;

    // Band lines and their names, which double as the legend.
    final grid = Paint()
      ..color = line
      ..strokeWidth = 1;
    for (final f in [1 / 3, 2 / 3]) {
      canvas.drawLine(Offset(0, y(f).roundToDouble() + 0.5), Offset(plotW, y(f).roundToDouble() + 0.5), grid);
    }
    final bands = [(RainLevel.light, 0.0, 1 / 3), (RainLevel.moderate, 1 / 3, 2 / 3), (RainLevel.heavy, 2 / 3, 1.0)];
    for (final (level, lo, hi) in bands) {
      final label = _text(level.label);
      final cy = (y(lo) + y(hi)) / 2;
      final left = plotW + 14;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(left + 3.5, cy), width: 7, height: 7),
          const Radius.circular(2),
        ),
        Paint()..color = colors.forLevel(level),
      );
      label.paint(canvas, Offset(left + 12, cy - label.height / 2));
    }

    // Radar steps, then the coarser model steps behind a dashed divider.
    final radarUntil = nowcast.radarUntil;
    final hasModel = radarUntil != null && radarUntil.isBefore(nowcast.end) && radarUntil.isAfter(start);
    if (hasModel) {
      final dx = x(radarUntil).roundToDouble() + 0.5;
      final dash = Paint()
        ..color = muted.withValues(alpha: 0.5)
        ..strokeWidth = 1;
      for (var yy = 0.0; yy < plotH; yy += 6) {
        canvas.drawLine(Offset(dx, yy), Offset(dx, math.min(yy + 3, plotH)), dash);
      }
      final caption = _text('Model', style: labelStyle.copyWith(fontSize: 10.5));
      if (dx + 6 + caption.width < plotW) caption.paint(canvas, Offset(dx + 6, 0));
      final radar = _text('Radar', style: labelStyle.copyWith(fontSize: 10.5));
      if (dx - 6 - radar.width > 0) radar.paint(canvas, Offset(dx - 6 - radar.width, 0));
    }

    for (var i = 0; i < pts.length; i++) {
      final pt = pts[i];
      final level = RainLevel.of(pt.mmPerHour);
      if (level == RainLevel.none) continue;
      final next = i + 1 < pts.length ? pts[i + 1].time : nowcast.end;
      final left = x(pt.time);
      final right = x(next);
      final gap = math.min(1.5, (right - left) * 0.25);
      final top = y(rainHeight(pt.mmPerHour));
      var color = colors.forLevel(level);
      if (selected != null && selected != i) color = color.withValues(alpha: color.a * 0.4);
      canvas.drawRRect(
        RRect.fromLTRBAndCorners(
          left + gap / 2,
          math.min(top, plotH - 3),
          right - gap / 2,
          plotH,
          topLeft: const Radius.circular(2),
          topRight: const Radius.circular(2),
        ),
        Paint()..color = color,
      );
    }

    // Baseline and time axis.
    canvas.drawLine(Offset(0, plotH + 0.5), Offset(plotW, plotH + 0.5), Paint()..color = muted.withValues(alpha: 0.45));
    final tick = Paint()
      ..color = muted.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    final nowLabel = _text(
      'Now',
      style: labelStyle.copyWith(color: ink, fontWeight: FontWeight.w600),
    );
    nowLabel.paint(canvas, Offset(0, plotH + 7));
    var lastRight = nowLabel.width + 8;
    final hm = DateFormat.Hm();
    final step = span <= 2.5 * 3600 ? 30 : 60;
    var t = DateTime(start.year, start.month, start.day, start.hour);
    while (!t.isAfter(nowcast.end)) {
      if (t.isAfter(start)) {
        final tx = x(t);
        canvas.drawLine(Offset(tx.roundToDouble() + 0.5, plotH), Offset(tx.roundToDouble() + 0.5, plotH + 4), tick);
        final label = _text(hm.format(t));
        final lx = tx - label.width / 2;
        if (lx > lastRight && lx + label.width <= plotW + 4) {
          label.paint(canvas, Offset(lx, plotH + 7));
          lastRight = lx + label.width + 8;
        }
      }
      t = t.add(Duration(minutes: step));
    }

    // The step under the finger.
    final sel = selected;
    if (sel != null && sel < pts.length) {
      final next = sel + 1 < pts.length ? pts[sel + 1].time : nowcast.end;
      final cx = ((x(pts[sel].time) + x(next)) / 2).roundToDouble() + 0.5;
      canvas.drawLine(
        Offset(cx, 0),
        Offset(cx, plotH),
        Paint()
          ..color = ink.withValues(alpha: 0.55)
          ..strokeWidth = 1,
      );
      canvas.drawCircle(Offset(cx, 2.5), 2.5, Paint()..color = ink);
    }
  }

  @override
  bool shouldRepaint(_RainPainter old) =>
      old.nowcast != nowcast ||
      old.selected != selected ||
      old.colors != colors ||
      old.line != line ||
      old.muted != muted ||
      old.ink != ink ||
      old.labelStyle != labelStyle;
}

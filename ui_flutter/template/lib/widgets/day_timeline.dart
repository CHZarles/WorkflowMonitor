import "package:flutter/material.dart";

import "../theme/tokens.dart";
import "entity_avatar.dart";

class DayTimelineLane {
  const DayTimelineLane({
    required this.kind,
    required this.entity,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.totalSeconds,
    required this.bars,
  });

  final String kind; // "app" | "domain"
  final String entity; // app id or hostname
  final String label;
  final String? subtitle;
  final IconData icon;
  final int totalSeconds;
  final List<DayTimelineBar> bars;
}

class DayTimelineBar {
  const DayTimelineBar({
    required this.startMinute,
    required this.endMinute,
    required this.audio,
    required this.tooltip,
    required this.startTs,
    required this.endTs,
  });

  final int startMinute; // 0..1440
  final int endMinute; // 0..1440
  final bool audio;
  final String tooltip;
  final String startTs; // RFC3339 (UTC)
  final String endTs; // RFC3339 (UTC)
}

class DayTimeline extends StatelessWidget {
  const DayTimeline({
    super.key,
    required this.lanes,
    this.labelWidth = 220,
    this.laneHeight = 56,
    this.barHeight = 18,
    this.showNowIndicator = true,
    this.zoom = 1.0,
    this.horizontalController,
    this.onLaneTap,
    this.onBarTap,
  });

  final List<DayTimelineLane> lanes;
  final double labelWidth;
  final double laneHeight;
  final double barHeight;
  final bool showNowIndicator;
  final double zoom;
  final ScrollController? horizontalController;
  final void Function(DayTimelineLane lane)? onLaneTap;
  final void Function(DayTimelineLane lane, DayTimelineBar bar)? onBarTap;

  List<int> _majorTicksMinutes() => const [0, 360, 720, 1080, 1440];
  List<int> _minorTicksMinutes() => List<int>.generate(23, (i) => (i + 1) * 60);

  String _formatDurationShort(int seconds) {
    final m = ((seconds + 30) / 60).floor();
    if (m < 60) return "${m}m";
    final h = m ~/ 60;
    final rm = m % 60;
    return rm == 0 ? "${h}h" : "${h}h ${rm}m";
  }

  String _tickLabel(int min) {
    final h = (min ~/ 60).clamp(0, 24);
    final hh = h.toString().padLeft(2, "0");
    return "$hh:00";
  }

  @override
  Widget build(BuildContext context) {
    if (lanes.isEmpty) {
      return Text(
        "No activity yet.",
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }

    final scheme = Theme.of(context).colorScheme;
    final gridColorMajor = scheme.onSurface.withValues(alpha: 0.10);
    final gridColorMinor = scheme.onSurface.withValues(alpha: 0.06);
    final labelColor = scheme.onSurfaceVariant;

    final chartHeight = (lanes.length * laneHeight).toDouble();
    final vPad = (((laneHeight - barHeight) / 2).clamp(0.0, 24.0)).toDouble();

    final int? nowMin = showNowIndicator
        ? (() {
            final now = DateTime.now();
            final dayStart = DateTime(now.year, now.month, now.day);
            return now.difference(dayStart).inMinutes.clamp(0, 1440);
          })()
        : null;

    Widget axisHeader(double width) {
      final major = _majorTicksMinutes();
      final minor = _minorTicksMinutes();
      final nowX = nowMin == null ? null : (width * (nowMin / 1440.0));
      return SizedBox(
        height: 24,
        child: Stack(
          children: [
            for (final t in minor)
              Positioned(
                left: width * (t / 1440.0),
                top: 0,
                bottom: 0,
                child: Container(width: 1, color: gridColorMinor),
              ),
            for (final t in major)
              Positioned(
                left: width * (t / 1440.0),
                top: 0,
                bottom: 0,
                child: Container(width: 1, color: gridColorMajor),
              ),
            if (nowX != null)
              Positioned(
                left: nowX.clamp(0.0, width - 1).toDouble(),
                top: 0,
                bottom: 0,
                child: Container(width: 2, color: scheme.primary.withValues(alpha: 0.60)),
              ),
            for (final t in major)
              Positioned(
                left: (width * (t / 1440.0) - 18).clamp(0.0, width - 48).toDouble(),
                top: 2,
                child: Text(
                  _tickLabel(t),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: labelColor),
                ),
              ),
          ],
        ),
      );
    }

    Widget timelineArea(double width) {
      final major = _majorTicksMinutes();
      final minor = _minorTicksMinutes();
      final nowX = nowMin == null ? null : (width * (nowMin / 1440.0));
      return SizedBox(
        height: chartHeight,
        child: Stack(
          children: [
            for (final t in minor)
              Positioned(
                left: width * (t / 1440.0),
                top: 0,
                bottom: 0,
                child: Container(width: 1, color: gridColorMinor),
              ),
            for (final t in major)
              Positioned(
                left: width * (t / 1440.0),
                top: 0,
                bottom: 0,
                child: Container(width: 1, color: gridColorMajor),
              ),
            if (nowX != null)
              Positioned(
                left: nowX.clamp(0.0, width - 1).toDouble(),
                top: 0,
                bottom: 0,
                child: Container(width: 2, color: scheme.primary.withValues(alpha: 0.60)),
              ),
            for (var i = 0; i < lanes.length; i++)
              Positioned(
                left: 0,
                right: 0,
                top: (i * laneHeight).toDouble(),
                height: laneHeight,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: gridColorMinor, width: 1),
                    ),
                  ),
                ),
              ),
            for (var i = 0; i < lanes.length; i++)
              for (final bar in lanes[i].bars)
                Positioned(
                  left: width * (bar.startMinute / 1440.0),
                  top: (i * laneHeight + vPad).toDouble(),
                  width: (width * ((bar.endMinute - bar.startMinute) / 1440.0)).clamp(2.0, width).toDouble(),
                  height: barHeight,
                  child: Tooltip(
                    message: bar.tooltip,
                    child: MouseRegion(
                      cursor: onBarTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: onBarTap == null ? null : () => onBarTap?.call(lanes[i], bar),
                          borderRadius: BorderRadius.circular(6),
                          child: Ink(
                            decoration: BoxDecoration(
                              color: _barColor(scheme, lanes[i].kind, bar.audio),
                              borderRadius: BorderRadius.circular(6),
                              border: bar.audio
                                  ? Border.all(color: scheme.onSurface.withValues(alpha: 0.20), width: 1)
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final chartWidth = (width - labelWidth).clamp(0.0, width).toDouble();
        final z = zoom.clamp(1.0, 6.0);
        final zoomedWidth = (chartWidth * z).clamp(chartWidth, chartWidth * 6.0).toDouble();
        final hCtrl = horizontalController;

        final labels = Column(
          children: [
            for (final lane in lanes)
              MouseRegion(
                cursor: onLaneTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
                child: InkWell(
                  onTap: onLaneTap == null ? null : () => onLaneTap?.call(lane),
                  child: SizedBox(
                    height: laneHeight,
                    child: Row(
                      children: [
                        EntityAvatar(
                          kind: lane.kind,
                          entity: lane.entity,
                          label: lane.label,
                          icon: lane.kind == "app" ? lane.icon : null,
                          size: 22,
                        ),
                        const SizedBox(width: RecorderTokens.space2),
                        Expanded(
                          child: Tooltip(
                            message: lane.subtitle == null
                                ? "${lane.label}\n${_formatDurationShort(lane.totalSeconds)}"
                                : "${lane.label}\n${lane.subtitle}\n${_formatDurationShort(lane.totalSeconds)}",
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  lane.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                if (lane.subtitle != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    lane.subtitle!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.labelSmall?.copyWith(color: labelColor),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: RecorderTokens.space2),
                        Text(
                          _formatDurationShort(lane.totalSeconds),
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: labelColor),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );

        Widget chartColumn() {
          final child = SizedBox(
            width: zoomedWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                axisHeader(zoomedWidth),
                const SizedBox(height: RecorderTokens.space2),
                ClipRRect(
                  borderRadius: BorderRadius.circular(RecorderTokens.radiusM.toDouble()),
                  child: timelineArea(zoomedWidth),
                ),
              ],
            ),
          );

          if (z <= 1.01) {
            return child;
          }

          if (hCtrl == null) {
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              primary: false,
              child: child,
            );
          }

          return Scrollbar(
            controller: hCtrl,
            thumbVisibility: true,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              controller: hCtrl,
              primary: false,
              child: child,
            ),
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: labelWidth,
              child: Column(
                children: [
                  const SizedBox(height: 24),
                  const SizedBox(height: RecorderTokens.space2),
                  labels,
                ],
              ),
            ),
            Expanded(child: chartColumn()),
          ],
        );
      },
    );
  }

  Color _barColor(ColorScheme scheme, String kind, bool audio) {
    final base = kind == "app" ? scheme.primaryContainer : scheme.secondaryContainer;
    return audio ? base.withValues(alpha: 0.55) : base;
  }
}

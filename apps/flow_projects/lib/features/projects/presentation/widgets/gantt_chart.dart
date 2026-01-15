import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flow_models/flow_models.dart';
import 'package:flow_projects/core/constants/app_colors.dart';
import 'package:flow_projects/core/constants/app_spacing.dart';
import 'package:flow_projects/core/providers/providers.dart';
import 'package:flow_projects/core/theme/flow_theme.dart';
import 'package:intl/intl.dart';

// Helper to get status color from TaskStatus
Color _getTaskStatusColor(TaskStatus status) {
  switch (status) {
    case TaskStatus.pending:
      return FlowColors.statusNotStarted;
    case TaskStatus.inProgress:
      return FlowColors.statusInProgress;
    case TaskStatus.completed:
      return FlowColors.statusCompleted;
    case TaskStatus.cancelled:
    case TaskStatus.archived:
      return FlowColors.error;
  }
}

class GanttChart extends ConsumerStatefulWidget {
  const GanttChart({super.key});

  @override
  ConsumerState<GanttChart> createState() => _GanttChartState();
}

class _GanttChartState extends ConsumerState<GanttChart> {
  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _verticalScrollController = ScrollController();

  // Zoom level: pixels per day
  double _dayWidth = 32.0;

  // Visible date range
  late DateTime _startDate;
  late DateTime _endDate;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month - 1, 1);
    _endDate = DateTime(now.year, now.month + 2, 0);
  }

  @override
  void dispose() {
    _horizontalScrollController.dispose();
    _verticalScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wbsNodesAsync = ref.watch(wbsNodesProvider);
    final colors = context.flowColors;

    return wbsNodesAsync.when(
      data: (nodes) {
        if (nodes.isEmpty) {
          return _buildEmptyState(context);
        }

        // Calculate date range from nodes
        _calculateDateRange(nodes);

        return Column(
          children: [
            // Toolbar
            _GanttToolbar(
              dayWidth: _dayWidth,
              onZoomIn: () {
                setState(() {
                  _dayWidth = (_dayWidth * 1.2).clamp(16.0, 64.0);
                });
              },
              onZoomOut: () {
                setState(() {
                  _dayWidth = (_dayWidth / 1.2).clamp(16.0, 64.0);
                });
              },
              onTodayPressed: _scrollToToday,
            ),

            // Gantt chart content
            Expanded(
              child: Row(
                children: [
                  // Left panel: Node names
                  Container(
                    width: 280,
                    decoration: BoxDecoration(
                      color: colors.surface,
                      border: Border(
                        right: BorderSide(color: colors.divider, width: 0.5),
                      ),
                    ),
                    child: Column(
                      children: [
                        // Header
                        Container(
                          height: FlowSpacing.ganttHeaderHeight,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: colors.sidebar,
                            border: Border(
                              bottom: BorderSide(color: colors.divider, width: 0.5),
                            ),
                          ),
                          child: Row(
                            children: [
                              Text(
                                'Task Name',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: colors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Node list
                        Expanded(
                          child: ListView.builder(
                            controller: _verticalScrollController,
                            itemCount: nodes.length,
                            itemBuilder: (context, index) {
                              final node = nodes[index];
                              return _GanttNodeLabel(node: node);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Right panel: Timeline
                  Expanded(
                    child: Column(
                      children: [
                        // Timeline header
                        _TimelineHeader(
                          startDate: _startDate,
                          endDate: _endDate,
                          dayWidth: _dayWidth,
                          scrollController: _horizontalScrollController,
                        ),

                        // Gantt bars
                        Expanded(
                          child: SingleChildScrollView(
                            controller: _horizontalScrollController,
                            scrollDirection: Axis.horizontal,
                            child: SizedBox(
                              width: _endDate.difference(_startDate).inDays * _dayWidth,
                              child: ListView.builder(
                                controller: _verticalScrollController,
                                itemCount: nodes.length,
                                itemBuilder: (context, index) {
                                  final node = nodes[index];
                                  return _GanttBar(
                                    node: node,
                                    startDate: _startDate,
                                    dayWidth: _dayWidth,
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text('Error: $error'),
          ],
        ),
      ),
    );
  }

  void _calculateDateRange(List<WBSNode> nodes) {
    if (nodes.isEmpty) return;

    DateTime? earliest;
    DateTime? latest;

    for (final node in nodes) {
      if (node.plannedStart != null) {
        if (earliest == null || node.plannedStart!.isBefore(earliest)) {
          earliest = node.plannedStart;
        }
      }
      if (node.plannedEnd != null) {
        if (latest == null || node.plannedEnd!.isAfter(latest)) {
          latest = node.plannedEnd;
        }
      }
    }

    if (earliest != null) {
      _startDate = earliest.subtract(const Duration(days: 7));
    }
    if (latest != null) {
      _endDate = latest.add(const Duration(days: 14));
    }
  }

  void _scrollToToday() {
    final today = DateTime.now();
    final offset = today.difference(_startDate).inDays * _dayWidth;
    _horizontalScrollController.animateTo(
      offset - 200, // Center roughly
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final colors = context.flowColors;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.view_timeline_outlined,
            size: 64,
            color: colors.textTertiary,
          ),
          const SizedBox(height: 16),
          Text(
            'No tasks to display',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: colors.textSecondary,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add tasks with dates to see them in the Gantt chart',
            style: TextStyle(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _GanttToolbar extends StatelessWidget {
  final double dayWidth;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onTodayPressed;

  const _GanttToolbar({
    required this.dayWidth,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onTodayPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          bottom: BorderSide(color: colors.divider, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // Zoom controls
          IconButton(
            icon: const Icon(Icons.remove, size: 18),
            onPressed: onZoomOut,
            tooltip: 'Zoom out',
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '${dayWidth.round()}px/day',
              style: TextStyle(
                fontSize: 12,
                color: colors.textTertiary,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add, size: 18),
            onPressed: onZoomIn,
            tooltip: 'Zoom in',
          ),
          const SizedBox(width: 16),
          // Today button
          OutlinedButton.icon(
            onPressed: onTodayPressed,
            icon: const Icon(Icons.today, size: 16),
            label: const Text('Today'),
          ),
          const Spacer(),
          // View options
          PopupMenuButton<String>(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Icon(Icons.tune, size: 18, color: colors.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    'Options',
                    style: TextStyle(color: colors.textSecondary),
                  ),
                ],
              ),
            ),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'dependencies',
                child: Text('Show Dependencies'),
              ),
              const PopupMenuItem(
                value: 'critical_path',
                child: Text('Show Critical Path'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TimelineHeader extends StatelessWidget {
  final DateTime startDate;
  final DateTime endDate;
  final double dayWidth;
  final ScrollController scrollController;

  const _TimelineHeader({
    required this.startDate,
    required this.endDate,
    required this.dayWidth,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final totalDays = endDate.difference(startDate).inDays;

    return Container(
      height: FlowSpacing.ganttHeaderHeight,
      decoration: BoxDecoration(
        color: colors.sidebar,
        border: Border(
          bottom: BorderSide(color: colors.divider, width: 0.5),
        ),
      ),
      child: SingleChildScrollView(
        controller: scrollController,
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: totalDays * dayWidth,
          child: CustomPaint(
            painter: _TimelineHeaderPainter(
              startDate: startDate,
              totalDays: totalDays,
              dayWidth: dayWidth,
              colors: colors,
            ),
          ),
        ),
      ),
    );
  }
}

class _TimelineHeaderPainter extends CustomPainter {
  final DateTime startDate;
  final int totalDays;
  final double dayWidth;
  final FlowColorScheme colors;

  _TimelineHeaderPainter({
    required this.startDate,
    required this.totalDays,
    required this.dayWidth,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final monthFormat = DateFormat('MMM yyyy');
    final dayFormat = DateFormat('d');
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    // Draw month labels
    DateTime currentMonth = DateTime(startDate.year, startDate.month);
    while (currentMonth.isBefore(startDate.add(Duration(days: totalDays)))) {
      final offsetDays = currentMonth.difference(startDate).inDays;
      final x = offsetDays * dayWidth;

      textPainter.text = TextSpan(
        text: monthFormat.format(currentMonth),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: colors.textSecondary,
        ),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(x + 8, 8));

      currentMonth = DateTime(currentMonth.year, currentMonth.month + 1);
    }

    // Draw day numbers (only if dayWidth is large enough)
    if (dayWidth >= 24) {
      for (int i = 0; i < totalDays; i++) {
        final date = startDate.add(Duration(days: i));
        final x = i * dayWidth;

        textPainter.text = TextSpan(
          text: dayFormat.format(date),
          style: TextStyle(
            fontSize: 10,
            color: date.weekday == DateTime.saturday ||
                    date.weekday == DateTime.sunday
                ? colors.textPlaceholder
                : colors.textTertiary,
          ),
        );
        textPainter.layout();
        textPainter.paint(
          canvas,
          Offset(x + (dayWidth - textPainter.width) / 2, 32),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _GanttNodeLabel extends StatelessWidget {
  final WBSNode node;

  const _GanttNodeLabel({required this.node});

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;

    return Container(
      height: FlowSpacing.ganttRowHeight,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colors.divider, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // Status dot
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _getTaskStatusColor(node.status),
            ),
          ),
          const SizedBox(width: 12),
          // Name
          Expanded(
            child: Text(
              node.title,
              style: TextStyle(
                fontSize: 13,
                color: colors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _GanttBar extends StatelessWidget {
  final WBSNode node;
  final DateTime startDate;
  final double dayWidth;

  const _GanttBar({
    required this.node,
    required this.startDate,
    required this.dayWidth,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;

    // If no dates, show empty row
    if (node.plannedStart == null && node.plannedEnd == null) {
      return Container(
        height: FlowSpacing.ganttRowHeight,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: colors.divider, width: 0.5),
          ),
        ),
      );
    }

    final nodeStart = node.plannedStart ?? node.plannedEnd!;
    final nodeEnd = node.plannedEnd ?? node.plannedStart!;

    final startOffset = nodeStart.difference(startDate).inDays;
    final duration = nodeEnd.difference(nodeStart).inDays + 1;

    final barColor = node.isMilestone ? FlowColors.ganttMilestone : FlowColors.ganttTask;

    return Container(
      height: FlowSpacing.ganttRowHeight,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colors.divider, width: 0.5),
        ),
      ),
      child: Stack(
        children: [
          // Today line
          _TodayLine(startDate: startDate, dayWidth: dayWidth),

          // Task bar
          Positioned(
            left: startOffset * dayWidth,
            top: 8,
            child: node.isMilestone
                ? _MilestoneMarker(color: barColor)
                : _TaskBar(
                    width: duration * dayWidth,
                    color: barColor,
                    progress: node.progress / 100.0,
                    name: node.title,
                  ),
          ),
        ],
      ),
    );
  }
}

class _TodayLine extends StatelessWidget {
  final DateTime startDate;
  final double dayWidth;

  const _TodayLine({required this.startDate, required this.dayWidth});

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final offset = today.difference(startDate).inDays * dayWidth + dayWidth / 2;

    return Positioned(
      left: offset,
      top: 0,
      bottom: 0,
      child: Container(
        width: 2,
        color: FlowColors.ganttToday.withOpacity(0.5),
      ),
    );
  }
}

class _TaskBar extends StatelessWidget {
  final double width;
  final Color color;
  final double progress;
  final String name;

  const _TaskBar({
    required this.width,
    required this.color,
    required this.progress,
    required this.name,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '$name (${(progress * 100).round()}%)',
      child: Container(
        width: width.clamp(4.0, double.infinity),
        height: 24,
        decoration: BoxDecoration(
          color: color.withOpacity(0.2),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color, width: 1),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: Stack(
            children: [
              // Progress fill
              FractionallySizedBox(
                widthFactor: progress,
                heightFactor: 1,
                child: Container(color: color.withOpacity(0.4)),
              ),
              // Label (if wide enough)
              if (width > 60)
                Positioned.fill(
                  child: Center(
                    child: Text(
                      name,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: color,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MilestoneMarker extends StatelessWidget {
  final Color color;

  const _MilestoneMarker({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.flag_rounded,
        size: 14,
        color: Colors.white,
      ),
    );
  }
}

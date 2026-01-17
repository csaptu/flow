import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flow_models/flow_models.dart';
import 'package:flow_tasks/core/providers/providers.dart';
import 'package:flow_tasks/core/theme/flow_theme.dart';
import 'package:flow_tasks/features/tasks/presentation/widgets/task_date_time_picker.dart';
import 'package:flow_tasks/features/tasks/presentation/widgets/move_to_list_picker.dart';
import 'package:flow_tasks/features/tasks/presentation/widgets/attachment_picker.dart';
import 'package:flow_tasks/features/tasks/presentation/widgets/markdown_description_field.dart';
import 'package:intl/intl.dart';

/// Task detail panel - shows on the right on desktop, bottom sheet on mobile
class TaskDetailPanel extends ConsumerStatefulWidget {
  final Task task;
  final VoidCallback onClose;
  final bool isBottomSheet;

  const TaskDetailPanel({
    super.key,
    required this.task,
    required this.onClose,
    this.isBottomSheet = false,
  });

  @override
  ConsumerState<TaskDetailPanel> createState() => _TaskDetailPanelState();
}

class _TaskDetailPanelState extends ConsumerState<TaskDetailPanel> {
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  bool _isCleaningTitle = false;
  bool _isCleaningDescription = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.task.title);
    _descriptionController =
        TextEditingController(text: widget.task.description ?? '');
  }

  @override
  void didUpdateWidget(covariant TaskDetailPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.task.id != widget.task.id) {
      _titleController.text = widget.task.title;
      _descriptionController.text = widget.task.description ?? '';
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _updateTitle() async {
    final newTitle = _titleController.text.trim();
    if (newTitle.isEmpty || newTitle == widget.task.title) return;

    final actions = ref.read(taskActionsProvider);
    await actions.update(widget.task.id, title: newTitle);
  }

  Future<void> _updateDescription() async {
    final newDesc = _descriptionController.text.trim();
    if (newDesc == (widget.task.description ?? '')) return;

    final actions = ref.read(taskActionsProvider);
    await actions.update(
      widget.task.id,
      description: newDesc.isEmpty ? null : newDesc,
    );
  }

  Future<void> _cleanTitle() async {
    setState(() => _isCleaningTitle = true);
    try {
      final aiActions = ref.read(aiActionsProvider);
      await aiActions.cleanTitle(widget.task.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isCleaningTitle = false);
    }
  }

  Future<void> _cleanDescription() async {
    setState(() => _isCleaningDescription = true);
    try {
      final aiActions = ref.read(aiActionsProvider);
      await aiActions.cleanDescription(widget.task.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isCleaningDescription = false);
    }
  }

  Future<void> _revertTitle() async {
    if (widget.task.originalTitle == null) return;
    final actions = ref.read(taskActionsProvider);
    await actions.update(
      widget.task.id,
      title: widget.task.originalTitle!,
      skipAutoCleanup: true,
    );
    _titleController.text = widget.task.originalTitle!;
  }

  Future<void> _revertDescription() async {
    if (widget.task.originalDescription == null) return;
    final actions = ref.read(taskActionsProvider);
    await actions.update(
      widget.task.id,
      description: widget.task.originalDescription,
      skipAutoCleanup: true,
    );
    _descriptionController.text = widget.task.originalDescription ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final task = widget.task;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: widget.isBottomSheet
            ? null
            : Border(
                left: BorderSide(color: colors.divider, width: 0.5),
              ),
        borderRadius: widget.isBottomSheet
            ? const BorderRadius.vertical(top: Radius.circular(16))
            : null,
      ),
      child: Column(
        children: [
          // Header (minimal)
          _buildHeader(context, colors, task),

          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Due date indicator
                  if (task.dueDate != null) _buildDueDateRow(colors, task),

                  if (task.dueDate != null) const SizedBox(height: 16),

                  // Title with inline clean/revert button and cleaned indicator
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Subtle cleaned indicator
                      if (task.titleWasCleaned)
                        Padding(
                          padding: const EdgeInsets.only(right: 6, top: 6),
                          child: Tooltip(
                            message: 'AI cleaned',
                            child: Icon(
                              Icons.auto_fix_high_rounded,
                              size: 12,
                              color: colors.textTertiary.withAlpha(120),
                            ),
                          ),
                        ),
                      Expanded(
                        child: TextField(
                          controller: _titleController,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            hintText: 'Task title',
                            contentPadding: EdgeInsets.zero,
                            isDense: true,
                            filled: false,
                          ),
                          maxLines: null,
                          onEditingComplete: _updateTitle,
                          onTapOutside: (_) => _updateTitle(),
                        ),
                      ),
                      // Inline clean/revert title button
                      if (_isCleaningTitle)
                        Padding(
                          padding: const EdgeInsets.only(left: 8, top: 4),
                          child: SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colors.textTertiary,
                            ),
                          ),
                        )
                      else if (task.titleWasCleaned)
                        InkWell(
                          onTap: _revertTitle,
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.only(left: 8, top: 4),
                            child: Text(
                              'revert',
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.textTertiary,
                              ),
                            ),
                          ),
                        )
                      else
                        InkWell(
                          onTap: _cleanTitle,
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.only(left: 8, top: 4),
                            child: Icon(
                              Icons.auto_fix_high_rounded,
                              size: 16,
                              color: colors.textTertiary,
                            ),
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Description with markdown support and clean/revert button
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Subtle cleaned indicator
                      if (task.descriptionWasCleaned)
                        Padding(
                          padding: const EdgeInsets.only(right: 6, top: 4),
                          child: Tooltip(
                            message: 'AI cleaned',
                            child: Icon(
                              Icons.auto_fix_high_rounded,
                              size: 12,
                              color: colors.textTertiary.withAlpha(120),
                            ),
                          ),
                        ),
                      Expanded(
                        child: MarkdownDescriptionField(
                          initialValue: task.description,
                          hintText: 'Add description... (supports markdown)',
                          onChanged: (value) {
                            _descriptionController.text = value;
                          },
                          onEditingComplete: _updateDescription,
                        ),
                      ),
                      // Inline clean/revert description button
                      if (_descriptionController.text.isNotEmpty || task.descriptionWasCleaned)
                        if (_isCleaningDescription)
                          Padding(
                            padding: const EdgeInsets.only(left: 8, top: 4),
                            child: SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colors.textTertiary,
                              ),
                            ),
                          )
                        else if (task.descriptionWasCleaned)
                          InkWell(
                            onTap: _revertDescription,
                            borderRadius: BorderRadius.circular(4),
                            child: Padding(
                              padding: const EdgeInsets.only(left: 8, top: 4),
                              child: Text(
                                'revert',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colors.textTertiary,
                                ),
                              ),
                            ),
                          )
                        else
                          InkWell(
                            onTap: _cleanDescription,
                            borderRadius: BorderRadius.circular(4),
                            child: Padding(
                              padding: const EdgeInsets.only(left: 8, top: 4),
                              child: Icon(
                                Icons.auto_fix_high_rounded,
                                size: 16,
                                color: colors.textTertiary,
                              ),
                            ),
                          ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // AI Steps (if any)
                  if (task.aiSteps.isNotEmpty) ...[
                    _buildStepsSection(colors, task),
                    const SizedBox(height: 24),
                  ],

                  // Tags only (no timestamps here)
                  if (task.tags.isNotEmpty) _buildTagsSection(colors, task),
                ],
              ),
            ),
          ),

          // Bottom toolbar with AI actions row
          _AIToolbar(task: task, onClose: widget.onClose),
        ],
      ),
    );
  }

  Widget _buildHeader(
      BuildContext context, FlowColorScheme colors, Task task) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colors.divider, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // Close button
          IconButton(
            icon: Icon(
              widget.isBottomSheet ? Icons.keyboard_arrow_down : Icons.close,
              color: colors.textSecondary,
            ),
            onPressed: widget.onClose,
            tooltip: 'Close',
          ),

          const Spacer(),

          // Priority indicator
          if (task.priority != Priority.none)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _getPriorityColor(task.priority.value).withAlpha(25),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.flag_rounded,
                    size: 14,
                    color: _getPriorityColor(task.priority.value),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _getPriorityLabel(task.priority.value),
                    style: TextStyle(
                      fontSize: 12,
                      color: _getPriorityColor(task.priority.value),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(width: 8),

          // More options (with timestamps)
          PopupMenuButton<String>(
            icon: Icon(Icons.more_horiz, color: colors.textSecondary),
            onSelected: (value) {
              // Handle menu actions if needed
            },
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                enabled: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Created ${_formatDateTime(task.createdAt)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textTertiary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Updated ${_formatDateTime(task.updatedAt)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDueDateRow(FlowColorScheme colors, Task task) {
    final isOverdue = task.isOverdue;
    final dateColor = isOverdue ? colors.error : colors.textSecondary;

    return InkWell(
      onTap: () async {
        final date = await TaskDateTimePicker.show(
          context,
          initialDate: task.dueDate,
          onClear: () async {
            final actions = ref.read(taskActionsProvider);
            await actions.update(task.id, dueDate: null);
          },
        );
        if (date != null) {
          final actions = ref.read(taskActionsProvider);
          await actions.update(task.id, dueDate: date);
        }
      },
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_outlined, size: 16, color: dateColor),
            const SizedBox(width: 8),
            Text(
              _formatDueDate(task.dueDate!),
              style: TextStyle(
                fontSize: 13,
                color: dateColor,
                fontWeight: isOverdue ? FontWeight.w500 : FontWeight.w400,
              ),
            ),
            if (isOverdue) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.error.withAlpha(25),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Overdue',
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.error,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStepsSection(FlowColorScheme colors, Task task) {
    final completed = task.aiSteps.where((s) => s.done).length;
    final total = task.aiSteps.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.checklist_rounded, size: 18, color: colors.textSecondary),
            const SizedBox(width: 8),
            Text(
              'Steps ($completed/$total)',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...task.aiSteps.map((step) => _buildStepItem(colors, step)),
      ],
    );
  }

  Widget _buildStepItem(FlowColorScheme colors, TaskStep step) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: Checkbox(
              value: step.done,
              onChanged: (value) {
                // TODO: Toggle step completion
              },
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              step.action,
              style: TextStyle(
                fontSize: 14,
                color: step.done ? colors.textTertiary : colors.textPrimary,
                decoration: step.done ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTagsSection(FlowColorScheme colors, Task task) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: task.tags
          .map((tag) => Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: colors.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  tag,
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.textSecondary,
                  ),
                ),
              ))
          .toList(),
    );
  }

  String _formatDueDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dateOnly = DateTime(date.year, date.month, date.day);

    if (dateOnly == today) {
      return 'Today';
    } else if (dateOnly == today.add(const Duration(days: 1))) {
      return 'Tomorrow';
    } else if (dateOnly == today.subtract(const Duration(days: 1))) {
      return 'Yesterday';
    } else {
      return DateFormat('MMM d, yyyy').format(date);
    }
  }

  String _formatDateTime(DateTime dt) {
    return DateFormat('MMM d, yyyy \'at\' h:mm a').format(dt);
  }

  Color _getPriorityColor(int priority) {
    switch (priority) {
      case 3:
        return const Color(0xFFE53935); // High - Red
      case 2:
        return const Color(0xFFFFA726); // Medium - Orange
      case 1:
        return const Color(0xFF42A5F5); // Low - Blue
      default:
        return Colors.grey;
    }
  }

  String _getPriorityLabel(int priority) {
    switch (priority) {
      case 3:
        return 'High';
      case 2:
        return 'Medium';
      case 1:
        return 'Low';
      default:
        return '';
    }
  }
}

/// Bottom toolbar with expandable AI actions row
class _AIToolbar extends ConsumerStatefulWidget {
  final Task task;
  final VoidCallback onClose;

  const _AIToolbar({required this.task, required this.onClose});

  @override
  ConsumerState<_AIToolbar> createState() => _AIToolbarState();
}

class _AIToolbarState extends ConsumerState<_AIToolbar> {
  bool _showAIActions = false;
  bool _isLoading = false;
  String? _loadingAction;

  // Bear app red color
  static const bearRed = Color(0xFFE53935);

  // AI action definitions - matches plan document
  // Free = no badge, Light = *, Premium = **
  static const _aiActions = [
    _AIAction('decompose', 'Steps', Icons.checklist_rounded, 1, AIFeature.decompose),
    _AIAction('complexity', 'Rate', Icons.speed_rounded, 1, AIFeature.complexity),
    _AIAction('entities', 'Extract', Icons.person_search_rounded, 1, AIFeature.entityExtraction),
    _AIAction('remind', 'Remind', Icons.alarm_rounded, 2, AIFeature.reminder),
    _AIAction('email', 'Email', Icons.email_outlined, 2, AIFeature.draftEmail),
    _AIAction('calendar', 'Invite', Icons.calendar_month_rounded, 2, AIFeature.draftCalendar),
  ];

  Future<void> _runAIAction(String action) async {
    setState(() {
      _isLoading = true;
      _loadingAction = action;
    });

    try {
      final aiActions = ref.read(aiActionsProvider);

      switch (action) {
        case 'decompose':
          await aiActions.decompose(widget.task.id);
          _showSnackBar('Steps generated');
          break;
        case 'complexity':
          final result = await aiActions.rate(widget.task.id);
          _showSnackBar('Complexity: ${result.complexity}/10 - ${result.reason}');
          break;
        case 'entities':
          final result = await aiActions.extract(widget.task.id);
          if (result.entities.isEmpty) {
            _showSnackBar('No entities found');
          } else {
            final summary = result.entities
                .map((e) => '${e.type}: ${e.value}')
                .take(3)
                .join(', ');
            _showSnackBar('Found: $summary');
          }
          break;
        case 'remind':
          final result = await aiActions.remind(widget.task.id);
          _showSnackBar('Reminder set: ${result.reason}');
          break;
        case 'email':
          final result = await aiActions.email(widget.task.id);
          _showDraftDialog(result.draft);
          break;
        case 'calendar':
          final result = await aiActions.invite(widget.task.id);
          _showDraftDialog(result.draft);
          break;
      }
    } catch (e) {
      _showSnackBar('Error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadingAction = null;
        });
      }
    }
  }

  void _showDraftDialog(dynamic draft) {
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(draft.type == 'email' ? 'Email Draft' : 'Calendar Invite'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (draft.type == 'email') ...[
                if (draft.to != null && draft.to!.isNotEmpty)
                  _buildDraftField('To', draft.to!),
                if (draft.subject != null)
                  _buildDraftField('Subject', draft.subject!),
                if (draft.body != null)
                  _buildDraftField('Body', draft.body!),
              ] else ...[
                if (draft.title != null)
                  _buildDraftField('Title', draft.title!),
                if (draft.startTime != null)
                  _buildDraftField('Start', draft.startTime!),
                if (draft.endTime != null)
                  _buildDraftField('End', draft.endTime!),
                if (draft.attendees.isNotEmpty)
                  _buildDraftField('Attendees', draft.attendees.join(', ')),
                if (draft.body != null)
                  _buildDraftField('Description', draft.body!),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _showSnackBar('Draft saved');
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget _buildDraftField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            value,
            style: const TextStyle(fontSize: 14),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
    }
  }

  String _getMimeType(String? extension) {
    switch (extension?.toLowerCase()) {
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      default:
        return 'application/octet-stream';
    }
  }

  String _formatDueDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dateOnly = DateTime(date.year, date.month, date.day);

    if (dateOnly == today) {
      return 'Today';
    } else if (dateOnly == today.add(const Duration(days: 1))) {
      return 'Tomorrow';
    } else if (dateOnly == today.subtract(const Duration(days: 1))) {
      return 'Yesterday';
    } else {
      return DateFormat('MMM d, yyyy').format(date);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final task = widget.task;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // AI Actions row (shown when wand is clicked) - minimal text style
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 200),
          crossFadeState: _showAIActions
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
          firstChild: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: colors.divider, width: 0.5),
              ),
            ),
            child: Row(
              children: _aiActions.map((action) {
                final isActionLoading = _loadingAction == action.id;
                final isLast = action == _aiActions.last;
                return Padding(
                  padding: EdgeInsets.only(right: isLast ? 0 : 16),
                  child: _AIActionText(
                    action: action,
                    isLoading: isActionLoading,
                    onTap: _isLoading ? null : () => _runAIAction(action.id),
                  ),
                );
              }).toList(),
            ),
          ),
          secondChild: const SizedBox(height: 0),
        ),

        // Main toolbar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: colors.divider, width: 0.5),
            ),
          ),
          child: Row(
            children: [
              // Date button
              IconButton(
                icon: Icon(
                  Icons.event_outlined,
                  color: task.dueDate != null ? colors.primary : colors.textSecondary,
                ),
                onPressed: () async {
                  final date = await TaskDateTimePicker.show(
                    context,
                    initialDate: task.dueDate,
                    onClear: () async {
                      final actions = ref.read(taskActionsProvider);
                      await actions.update(task.id, dueDate: null);
                    },
                  );
                  if (date != null) {
                    final actions = ref.read(taskActionsProvider);
                    await actions.update(task.id, dueDate: date);
                  }
                },
                tooltip: task.dueDate != null ? _formatDueDate(task.dueDate!) : 'Due Date',
                iconSize: 20,
              ),

              // List button
              IconButton(
                icon: Icon(Icons.tag, color: colors.textSecondary),
                onPressed: () async {
                  final selectedList = await MoveToListPicker.show(context, task);
                  if (selectedList != null) {
                    final actions = ref.read(taskActionsProvider);
                    await actions.update(
                      task.id,
                      tags: [...task.tags, 'list:${selectedList.fullPath}'],
                    );
                  }
                },
                tooltip: 'Move to List',
                iconSize: 20,
              ),

              // Attach button
              IconButton(
                icon: Icon(Icons.attach_file_outlined, color: colors.textSecondary),
                onPressed: () async {
                  final result = await AttachmentPicker.show(context);
                  if (result == null) return;

                  final attachActions = ref.read(attachmentActionsProvider(task.id));

                  try {
                    if (result.type == AttachmentPickerType.link && result.url != null) {
                      await attachActions.addLink(result.url!);
                    } else if (result.type == AttachmentPickerType.file && result.file != null) {
                      final file = result.file!;
                      final bytes = file.bytes ?? await file.readStream?.fold<List<int>>([], (prev, chunk) => prev..addAll(chunk));
                      if (bytes != null) {
                        await attachActions.uploadFile(
                          fileBytes: bytes,
                          filename: file.name,
                          mimeType: _getMimeType(file.extension),
                        );
                      }
                    } else if (result.type == AttachmentPickerType.image && result.image != null) {
                      final image = result.image!;
                      final bytes = await image.readAsBytes();
                      await attachActions.uploadFile(
                        fileBytes: bytes,
                        filename: image.name,
                        mimeType: image.mimeType ?? 'image/jpeg',
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to upload: $e')),
                      );
                    }
                  }
                },
                tooltip: 'Attach',
                iconSize: 20,
              ),

              // AI Magic Wand button (toggles AI row)
              IconButton(
                icon: Icon(
                  Icons.auto_fix_high_rounded,
                  color: _showAIActions ? bearRed : colors.textSecondary,
                ),
                onPressed: () {
                  setState(() => _showAIActions = !_showAIActions);
                },
                tooltip: 'AI Actions',
                iconSize: 20,
              ),

              const Spacer(),

              // Move to trash button
              IconButton(
                icon: Icon(Icons.delete_outline, color: colors.error),
                onPressed: () async {
                  final actions = ref.read(taskActionsProvider);
                  await actions.update(task.id, status: 'cancelled');
                  widget.onClose();
                },
                tooltip: 'Move to Trash',
                iconSize: 20,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// AI Action definition - matches plan document
class _AIAction {
  final String id;
  final String label;
  final IconData icon;
  final int tier; // 0=Free, 1=Light(*), 2=Premium(**)
  final AIFeature feature;

  const _AIAction(this.id, this.label, this.icon, this.tier, this.feature);
}

/// AI Action button with icon
class _AIActionText extends StatelessWidget {
  final _AIAction action;
  final bool isLoading;
  final VoidCallback? onTap;

  const _AIActionText({
    required this.action,
    required this.isLoading,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading)
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: colors.textTertiary,
                ),
              )
            else
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    action.icon,
                    size: 20,
                    color: colors.textTertiary,
                  ),
                  // Tier badge
                  if (action.tier > 0)
                    Positioned(
                      top: -4,
                      right: -6,
                      child: Text(
                        action.tier == 1 ? '*' : '**',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: action.tier == 1
                              ? const Color(0xFF4CAF50)
                              : const Color(0xFFFFB300),
                        ),
                      ),
                    ),
                ],
              ),
            const SizedBox(height: 2),
            Text(
              action.label,
              style: TextStyle(
                fontSize: 10,
                color: colors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

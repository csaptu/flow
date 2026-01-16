import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flow_models/flow_models.dart';
import 'package:flow_tasks/core/providers/providers.dart';
import 'package:flow_tasks/core/theme/flow_theme.dart';
import 'package:flow_tasks/features/tasks/presentation/widgets/task_date_time_picker.dart';
import 'package:flow_tasks/features/tasks/presentation/widgets/move_to_list_picker.dart';
import 'package:flow_tasks/features/tasks/presentation/widgets/attachment_picker.dart';
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
          // Header
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

                  const SizedBox(height: 16),

                  // Title (editable)
                  TextField(
                    controller: _titleController,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Task title',
                      contentPadding: EdgeInsets.zero,
                      filled: false,
                    ),
                    maxLines: null,
                    onEditingComplete: _updateTitle,
                    onTapOutside: (_) => _updateTitle(),
                  ),

                  const SizedBox(height: 16),

                  // Description (editable)
                  TextField(
                    controller: _descriptionController,
                    style: TextStyle(
                      fontSize: 15,
                      color: colors.textSecondary,
                      height: 1.5,
                    ),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Add description...',
                      hintStyle: TextStyle(color: colors.textPlaceholder),
                      contentPadding: EdgeInsets.zero,
                      filled: false,
                    ),
                    maxLines: null,
                    minLines: 3,
                    onTapOutside: (_) => _updateDescription(),
                  ),

                  const SizedBox(height: 24),

                  // AI Steps (if any)
                  if (task.aiSteps.isNotEmpty) ...[
                    _buildStepsSection(colors, task),
                    const SizedBox(height: 24),
                  ],

                  // Metadata section
                  _buildMetadataSection(colors, task),
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

          // More options
          IconButton(
            icon: Icon(Icons.more_horiz, color: colors.textSecondary),
            onPressed: () {
              // TODO: Show more options menu
            },
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
          initialDate: task.dueDate, // Navigate calendar to the due date
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

  Widget _buildMetadataSection(FlowColorScheme colors, Task task) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Tags
        if (task.tags.isNotEmpty) ...[
          Wrap(
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
          ),
          const SizedBox(height: 16),
        ],

        // Created/Updated info
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
    );
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

  // AI action definitions with tier badges
  // Tier 0 = Free, Tier 1 = Light (*), Tier 2 = Premium (**)
  static const _aiActions = [
    _AIAction('clean', Icons.cleaning_services_outlined, 'Clean up', 0),
    _AIAction('steps', Icons.account_tree_outlined, 'Break into steps', 1),
    _AIAction('complexity', Icons.analytics_outlined, 'Complexity', 1),
    _AIAction('extract', Icons.content_paste_search_outlined, 'Extract', 1),
    _AIAction('reminder', Icons.notifications_outlined, 'Reminder', 2),
    _AIAction('email', Icons.email_outlined, 'Email', 2),
    _AIAction('calendar', Icons.calendar_month_outlined, 'Calendar', 2),
    _AIAction('solution', Icons.lightbulb_outline, 'Solutions', 2),
  ];

  Future<void> _runAIAction(String action) async {
    setState(() {
      _isLoading = true;
      _loadingAction = action;
    });

    try {
      final aiActions = ref.read(aiActionsProvider);

      switch (action) {
        case 'clean':
          await aiActions.clean(widget.task.id);
          _showSnackBar('Task cleaned up');
          break;
        case 'steps':
          await aiActions.decompose(widget.task.id);
          _showSnackBar('Task broken into steps');
          break;
        case 'complexity':
          _showSnackBar('Complexity assessment coming soon');
          break;
        case 'extract':
          _showSnackBar('Extract information coming soon');
          break;
        case 'reminder':
          _showSnackBar('Reminder coming soon');
          break;
        case 'email':
          _showSnackBar('Draft email coming soon');
          break;
        case 'calendar':
          _showSnackBar('Calendar invite coming soon');
          break;
        case 'solution':
          _showSnackBar('Solution planning coming soon');
          break;
      }
    } catch (e) {
      _showSnackBar('AI error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadingAction = null;
        });
      }
    }
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
        // AI Actions row (shown when wand is clicked)
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 200),
          crossFadeState: _showAIActions
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
          firstChild: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: colors.surfaceVariant.withAlpha(100),
              border: Border(
                top: BorderSide(color: colors.divider, width: 0.5),
              ),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _aiActions.map((action) {
                  final isActionLoading = _loadingAction == action.id;
                  return Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: _AIActionChip(
                      action: action,
                      isLoading: isActionLoading,
                      onTap: _isLoading ? null : () => _runAIAction(action.id),
                    ),
                  );
                }).toList(),
              ),
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

/// AI Action definition
class _AIAction {
  final String id;
  final IconData icon;
  final String label;
  final int tier; // 0=Free, 1=Light(*), 2=Premium(**)

  const _AIAction(this.id, this.icon, this.label, this.tier);
}

/// AI Action chip with tier badge
class _AIActionChip extends StatelessWidget {
  final _AIAction action;
  final bool isLoading;
  final VoidCallback? onTap;

  const _AIActionChip({
    required this.action,
    required this.isLoading,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;

    return Tooltip(
      message: action.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.divider),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isLoading)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _AIToolbarState.bearRed,
                  ),
                )
              else
                Icon(action.icon, size: 16, color: colors.textSecondary),
              const SizedBox(width: 6),
              Text(
                action.label,
                style: TextStyle(
                  fontSize: 12,
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              // Tier badge
              if (action.tier > 0) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: action.tier == 1
                        ? const Color(0xFF4CAF50).withAlpha(30)
                        : const Color(0xFFFFB300).withAlpha(30),
                    borderRadius: BorderRadius.circular(4),
                  ),
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
            ],
          ),
        ),
      ),
    );
  }
}

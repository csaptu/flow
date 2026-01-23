import 'dart:async';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flow_models/flow_models.dart';
import 'package:flow_tasks/core/constants/app_spacing.dart';
import 'package:flow_tasks/core/providers/providers.dart';
import 'package:flow_tasks/core/theme/flow_theme.dart';
import 'package:flow_tasks/features/tasks/presentation/widgets/task_date_time_picker.dart';
import 'package:flow_tasks/features/tasks/presentation/widgets/attachment_picker.dart';
import 'package:flow_tasks/features/tasks/presentation/widgets/attachment_list.dart';
import 'package:flow_tasks/features/tasks/presentation/widgets/markdown_description_field.dart';
import 'package:flow_tasks/features/tasks/presentation/widgets/ai_cooking_dialog.dart';
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
  // Local state for dueAt - single source of truth for display
  DateTime? _localDueDate;
  // Debounce timers for auto-save while typing
  Timer? _titleDebounce;
  Timer? _descriptionDebounce;
  static const _debounceDuration = Duration(milliseconds: 800);
  // Track pending attachment deletions for optimistic UI
  final Set<String> _pendingAttachmentDeletions = {};

  @override
  void initState() {
    super.initState();
    // Use display fields (AI cleaned version or original)
    _titleController = TextEditingController(text: widget.task.displayTitle);
    _descriptionController =
        TextEditingController(text: widget.task.displayDescription ?? widget.task.description ?? '');
    _localDueDate = widget.task.dueAt;
  }

  @override
  void didUpdateWidget(covariant TaskDetailPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only update controllers when a DIFFERENT task is selected
    // Don't update on same task data changes - user might be editing
    if (oldWidget.task.id != widget.task.id) {
      _titleController.text = widget.task.displayTitle;
      _descriptionController.text = widget.task.displayDescription ?? widget.task.description ?? '';
      _localDueDate = widget.task.dueAt;
      _pendingAttachmentDeletions.clear(); // Clear pending deletions for new task
    }
  }

  @override
  void dispose() {
    _titleDebounce?.cancel();
    _descriptionDebounce?.cancel();
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _onTitleChanged(String value) {
    _titleDebounce?.cancel();
    _titleDebounce = Timer(_debounceDuration, _updateTitle);
  }

  void _onDescriptionChanged(String value) {
    _descriptionDebounce?.cancel();
    _descriptionDebounce = Timer(_debounceDuration, _updateDescription);
  }

  Future<void> _updateTitle() async {
    // Cancel pending debounce to avoid double save
    _titleDebounce?.cancel();

    final newTitle = _titleController.text.trim();
    if (newTitle.isEmpty || newTitle == widget.task.title) return;

    final actions = ref.read(taskActionsProvider);
    await actions.update(widget.task.id, title: newTitle);
  }

  Future<void> _updateDescription() async {
    // Cancel pending debounce to avoid double save
    _descriptionDebounce?.cancel();

    final newDesc = _descriptionController.text.trim();
    if (newDesc == (widget.task.description ?? '')) return;

    final actions = ref.read(taskActionsProvider);
    await actions.update(
      widget.task.id,
      description: newDesc.isEmpty ? null : newDesc,
    );
  }

  /// Handle pasted image - upload as attachment and return the 1-based image index
  Future<int?> _handleImagePaste(Uint8List imageBytes, String mimeType) async {
    try {
      // Get current image count BEFORE uploading
      final attachmentsAsync = ref.read(taskAttachmentsProvider(widget.task.id));
      final previousImageCount = attachmentsAsync.whenOrNull(
        data: (attachments) => attachments.where((a) => a.isImage).length,
      ) ?? 0;

      final attachmentActions = ref.read(attachmentActionsProvider(widget.task.id));
      final ext = mimeType.split('/').last;
      final filename = 'pasted-image-${DateTime.now().millisecondsSinceEpoch}.$ext';

      await attachmentActions.uploadFile(
        fileBytes: imageBytes,
        filename: filename,
        mimeType: mimeType,
      );

      // Return 1-based index: previous count + 1
      return previousImageCount + 1;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload image: $e')),
        );
      }
      return null;
    }
  }

  /// Resolve image index (1-based) to image URL
  /// [img1] = 1st image attachment, [img2] = 2nd image attachment, etc.
  String? _resolveImageUrl(int imageIndex) {
    final attachmentsAsync = ref.read(taskAttachmentsProvider(widget.task.id));
    return attachmentsAsync.whenOrNull(
      data: (attachments) {
        final images = attachments.where((a) => a.isImage).toList();
        // imageIndex is 1-based, convert to 0-based
        final idx = imageIndex - 1;
        if (idx >= 0 && idx < images.length) {
          return images[idx].url;
        }
        return null;
      },
    );
  }

  Future<void> _cleanTitle() async {
    final aiActions = ref.read(aiActionsProvider);
    Task? updatedTask;

    final result = await AICookingDialog.show(
      context: context,
      actionName: 'Cleaning up title',
      action: () async {
        updatedTask = await aiActions.cleanTitle(widget.task.id);
      },
    );

    // Update the controller with the new display title if completed
    if (result == AICookingResult.completed && updatedTask != null && mounted) {
      _titleController.text = updatedTask!.displayTitle;
    }
  }

  Future<void> _cleanDescription() async {
    final aiActions = ref.read(aiActionsProvider);
    Task? updatedTask;

    final result = await AICookingDialog.show(
      context: context,
      actionName: 'Cleaning up description',
      action: () async {
        updatedTask = await aiActions.cleanDescription(widget.task.id);
      },
    );

    // Update the controller with the new display description if completed
    if (result == AICookingResult.completed && updatedTask != null && mounted) {
      _descriptionController.text = updatedTask!.displayDescription ?? updatedTask!.description ?? '';
    }
  }

  /// Revert title to original (clear AI cleaned version)
  /// With new schema, original is always in title, we just need to clear aiCleanedTitle
  Future<void> _revertTitle() async {
    if (widget.task.aiCleanedTitle == null) return;
    final actions = ref.read(taskActionsProvider);
    // Call AI revert endpoint to clear aiCleanedTitle
    await actions.aiRevert(widget.task.id);
    // Show the original title
    _titleController.text = widget.task.title;
  }

  /// Revert description to original (clear AI cleaned version)
  /// With new schema, original is always in description, we just need to clear aiCleanedDescription
  Future<void> _revertDescription() async {
    if (widget.task.aiCleanedDescription == null) return;
    final actions = ref.read(taskActionsProvider);
    // Call AI revert endpoint to clear aiCleanedDescription
    await actions.aiRevert(widget.task.id);
    // Show the original description
    _descriptionController.text = widget.task.description ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    // Watch the task from provider to get live updates (e.g., after date change)
    final task = ref.watch(selectedTaskProvider) ?? widget.task;

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
                  // Due date indicator - use local state as source of truth
                  if (_localDueDate != null) ...[
                    _buildDueDateRow(colors, task),
                    const SizedBox(height: 16),
                  ],

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
                              Icons.brush_rounded,
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
                          onChanged: _onTitleChanged,
                          onEditingComplete: _updateTitle,
                          onTapOutside: (_) => _updateTitle(),
                        ),
                      ),
                      // Inline clean/revert title button
                      if (task.titleWasCleaned)
                        Tooltip(
                          message: 'Restore your input',
                          child: InkWell(
                            onTap: _revertTitle,
                            borderRadius: BorderRadius.circular(4),
                            child: Padding(
                              padding: const EdgeInsets.only(left: 8, top: 4),
                              child: Icon(
                                Icons.undo_rounded,
                                size: 16,
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
                              Icons.brush_rounded,
                              size: 16,
                              color: colors.textTertiary,
                            ),
                          ),
                        ),
                    ],
                  ),

                  // Task ID (debug mode only)
                  if (kDebugMode)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          Text(
                            task.id,
                            style: TextStyle(
                              fontSize: 10,
                              color: colors.textTertiary.withAlpha(150),
                              fontFamily: 'monospace',
                            ),
                          ),
                          const SizedBox(width: 4),
                          InkWell(
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: task.id));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Task ID copied'),
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(4),
                            child: Padding(
                              padding: const EdgeInsets.all(2),
                              child: Icon(
                                Icons.copy_rounded,
                                size: 12,
                                color: colors.textTertiary.withAlpha(150),
                              ),
                            ),
                          ),
                        ],
                      ),
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
                              Icons.brush_rounded,
                              size: 12,
                              color: colors.textTertiary.withAlpha(120),
                            ),
                          ),
                        ),
                      Expanded(
                        child: MarkdownDescriptionField(
                          initialValue: task.description,
                          hintText: 'Add description...',
                          onChanged: (value) {
                            _descriptionController.text = value;
                            _onDescriptionChanged(value);
                          },
                          onEditingComplete: _updateDescription,
                          onImagePaste: (imageBytes, mimeType) => _handleImagePaste(imageBytes, mimeType),
                          imageUrlResolver: (attachmentId) => _resolveImageUrl(attachmentId),
                        ),
                      ),
                      // Inline clean/revert description button
                      if (_descriptionController.text.isNotEmpty || task.descriptionWasCleaned)
                        if (task.descriptionWasCleaned)
                          Tooltip(
                            message: 'Restore your input',
                            child: InkWell(
                              onTap: _revertDescription,
                              borderRadius: BorderRadius.circular(4),
                              child: Padding(
                                padding: const EdgeInsets.only(left: 8, top: 4),
                                child: Icon(
                                  Icons.undo_rounded,
                                  size: 16,
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
                                Icons.brush_rounded,
                                size: 16,
                                color: colors.textTertiary,
                              ),
                            ),
                          ),
                    ],
                  ),

                  // Attachments section
                  _buildAttachmentsSection(colors, task),

                  // Entities section (AI-extracted) - only show if valid types exist
                  if (task.entities.any((e) => const {'person', 'location', 'place', 'organization'}.contains(e.type))) ...[
                    const SizedBox(height: 16),
                    _buildEntitiesSection(colors, task),
                  ],

                  const SizedBox(height: 24),

                  // Subtasks section (always show for root tasks to allow adding)
                  if (task.depth == 0)
                    _SubtasksSection(taskId: task.id, parentTask: task),

                  // Tags only (no timestamps here)
                  if (task.tags.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _buildTagsSection(colors, task),
                  ],
                ],
              ),
            ),
          ),

          // Bottom toolbar with AI actions row
          _AIToolbar(
            task: task,
            onClose: widget.onClose,
            localDueDate: _localDueDate,
            onDateChanged: (date) => setState(() => _localDueDate = date),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(
      BuildContext context, FlowColorScheme colors, Task task) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colors.divider, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // Priority indicator
          if (task.priority != Priority.none)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _getPriorityColor(task.priority.value).withAlpha(25),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.flag_rounded,
                    size: 12,
                    color: _getPriorityColor(task.priority.value),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _getPriorityLabel(task.priority.value),
                    style: TextStyle(
                      fontSize: 11,
                      color: _getPriorityColor(task.priority.value),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

          const Spacer(),

          // Close button - simple text link style
          GestureDetector(
            onTap: () async {
              // Save any pending changes before closing
              await _updateTitle();
              await _updateDescription();
              ref.read(isNewlyCreatedTaskProvider.notifier).state = false;
              widget.onClose();
            },
            child: Text(
              'Close',
              style: TextStyle(
                fontSize: 14,
                color: colors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDueDateRow(FlowColorScheme colors, Task task) {
    // Use task's isOverdue which properly handles time-based overdue
    final isOverdue = task.isOverdue;
    final dateColor = isOverdue ? colors.error : colors.textSecondary;

    return InkWell(
      onTap: () async {
        final taskId = task.id; // Capture task ID before async gap
        final date = await TaskDateTimePicker.show(
          context,
          initialDate: _localDueDate,
          hasTime: task.hasDueTime,
          onClear: () async {
            // Update local state immediately
            setState(() => _localDueDate = null);
            // Then update the store with clearDueAt flag
            final actions = ref.read(taskActionsProvider);
            await actions.update(taskId, clearDueAt: true);
          },
        );
        if (date != null && mounted) {
          // Update local state immediately for instant feedback
          setState(() => _localDueDate = date);
          // Then update the store (will sync in background)
          final actions = ref.read(taskActionsProvider);
          // Extract time if set (non-midnight means time was selected)
          final hasTime = date.hour != 0 || date.minute != 0;
          await actions.update(taskId, dueAt: date, hasDueTime: hasTime);
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
              _formatDueDate(_localDueDate!, task.hasDueTime),
              style: TextStyle(
                fontSize: 13,
                color: dateColor,
                fontWeight: isOverdue ? FontWeight.w600 : FontWeight.w400,
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
            // Duplicate warning badge - clickable to show saved duplicates
            if (task.hasDuplicateWarning) ...[
              const SizedBox(width: 8),
              Tooltip(
                message: 'Tap to view similar tasks',
                child: InkWell(
                  onTap: _showSavedDuplicatesDialog,
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFA726).withAlpha(25),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.find_replace_rounded,
                          size: 10,
                          color: const Color(0xFFFFA726),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Similar?',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFFFFA726),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
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

  Widget _buildAttachmentsSection(FlowColorScheme colors, Task task) {
    final attachmentsAsync = ref.watch(taskAttachmentsProvider(task.id));

    return attachmentsAsync.when(
      data: (allAttachments) {
        // Filter out pending deletions for optimistic UI
        final attachments = allAttachments
            .where((a) => !_pendingAttachmentDeletions.contains(a.id))
            .toList();

        if (attachments.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Section header
              Row(
                children: [
                  Icon(
                    Icons.attach_file,
                    size: 14,
                    color: colors.textTertiary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Attachments',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: colors.textTertiary,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '(${attachments.length})',
                    style: TextStyle(
                      fontSize: 10,
                      color: colors.textTertiary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              AttachmentList(
                attachments: attachments,
                onDelete: (attachment) async {
                  // Optimistically remove from UI
                  setState(() {
                    _pendingAttachmentDeletions.add(attachment.id);
                  });

                  try {
                    final attachActions = ref.read(attachmentActionsProvider(task.id));
                    await attachActions.delete(attachment.id);
                  } catch (e) {
                    // Restore on failure
                    if (mounted) {
                      setState(() {
                        _pendingAttachmentDeletions.remove(attachment.id);
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to delete attachment: $e')),
                      );
                    }
                  }
                },
                compact: true,
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildEntitiesSection(FlowColorScheme colors, Task task) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Row(
          children: [
            Icon(
              Icons.lightbulb_outline,
              size: 14,
              color: colors.textTertiary,
            ),
            const SizedBox(width: 6),
            Text(
              'Extracted Info',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: colors.textTertiary,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Entity chips - only show person, location, place, organization
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: task.entities
              .where((e) => const {'person', 'location', 'place', 'organization'}.contains(e.type))
              .map((entity) {
            return _EntityChipWithPopup(
              entity: entity,
              taskId: task.id,
              onNavigateToSmartList: () => _navigateToSmartList(entity),
              onRemoveEntity: () => _removeEntityFromTask(entity),
            );
          }).toList(),
        ),
      ],
    );
  }

  void _navigateToSmartList(AIEntity entity) {
    ref.read(selectedSmartListProvider.notifier).state = (type: entity.type, value: entity.value);
    ref.read(selectedSidebarIndexProvider.notifier).state = 200;
    ref.read(selectedListIdProvider.notifier).state = null;
    // Expand Smart Lists section in sidebar
    ref.read(smartListsExpandedProvider.notifier).state = true;
    widget.onClose();
  }

  Future<void> _removeEntityFromTask(AIEntity entity) async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove this chip?'),
        content: Text('Remove "${entity.value}" from this task?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final actions = ref.read(taskActionsProvider);
      await actions.removeEntityFromTask(widget.task.id, entity.type, entity.value);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Removed "${entity.value}"')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to remove: $e')),
        );
      }
    }
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

  String _formatDueDate(DateTime date, bool hasDueTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dateOnly = DateTime(date.year, date.month, date.day);

    String dateStr;
    if (dateOnly == today) {
      dateStr = 'Today';
    } else if (dateOnly == today.add(const Duration(days: 1))) {
      dateStr = 'Tomorrow';
    } else if (dateOnly == today.subtract(const Duration(days: 1))) {
      dateStr = 'Yesterday';
    } else {
      dateStr = DateFormat('MMM d, yyyy').format(date);
    }

    // Add time only if hasDueTime flag is set (authoritative source)
    // Don't use date.hour/minute fallback as timezone conversion can make
    // midnight UTC appear as non-midnight local time
    if (hasDueTime) {
      final timeStr = DateFormat('h:mm a').format(date);
      return '$dateStr, $timeStr';
    }

    return dateStr;
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

  /// Show dialog with previously saved duplicate tasks (from duplicate_of field)
  void _showSavedDuplicatesDialog() {
    if (!mounted || widget.task.duplicateOf.isEmpty) return;

    // Look up tasks from local store by IDs
    final localState = ref.read(localTaskStoreProvider);
    final duplicateTasks = <Task>[];

    for (final taskId in widget.task.duplicateOf) {
      // Check both server and optimistic tasks
      final task = localState.serverTasks[taskId] ?? localState.optimisticTasks[taskId];
      if (task != null && !localState.deletedTaskIds.contains(taskId)) {
        duplicateTasks.add(task);
      }
    }

    if (duplicateTasks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Similar tasks no longer exist')),
      );
      // Auto-resolve since there are no duplicates left
      final aiActions = ref.read(aiActionsProvider);
      aiActions.resolveDuplicate(widget.task.id);
      return;
    }

    showDialog(
      context: context,
      builder: (dialogContext) => _SimilarTasksDialog(
        currentTask: widget.task,
        similarTasks: duplicateTasks,
        reason: 'Previously found similar tasks',
        onResolveDuplicate: () async {
          final aiActions = ref.read(aiActionsProvider);
          await aiActions.resolveDuplicate(widget.task.id);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Marked as not duplicate')),
          );
        },
        onDeleteTask: (taskId) async {
          final actions = ref.read(taskActionsProvider);
          await actions.delete(taskId);
        },
      ),
    );
  }
}

/// Bottom toolbar with expandable AI actions row
class _AIToolbar extends ConsumerStatefulWidget {
  final Task task;
  final VoidCallback onClose;
  final DateTime? localDueDate;
  final ValueChanged<DateTime?> onDateChanged;

  const _AIToolbar({
    required this.task,
    required this.onClose,
    required this.localDueDate,
    required this.onDateChanged,
  });

  @override
  ConsumerState<_AIToolbar> createState() => _AIToolbarState();
}

class _AIToolbarState extends ConsumerState<_AIToolbar> {
  bool _showAIActions = false;
  bool _isLoading = false;
  String? _loadingAction;

  // Bear app red color
  static const bearRed = Color(0xFFE53935);

  // AI action definitions - only implemented features
  // Free = no badge, Light = *, Premium = **
  static const _aiActions = [
    _AIAction('decompose', 'Subtasks', Icons.checklist_rounded, 1, AIFeature.decompose),
    _AIAction('entities', 'Extract', Icons.person_search_rounded, 1, AIFeature.entityExtraction),
    _AIAction('duplicates', 'Similar', Icons.find_replace_rounded, 1, AIFeature.duplicateCheck),
  ];

  Future<void> _runAIAction(String action) async {
    // Check online status first
    final isOnline = ref.read(isOnlineProvider);
    if (!isOnline) {
      _showOfflineTooltip();
      return;
    }

    final actionName = _getActionDisplayName(action);
    final aiActions = ref.read(aiActionsProvider);

    // Variables to capture results for post-dialog handling
    dynamic actionResult;
    String? errorMessage;

    final result = await AICookingDialog.show(
      context: context,
      actionName: actionName,
      action: () async {
        try {
          switch (action) {
            case 'decompose':
              await aiActions.decompose(widget.task.id);
              break;
            case 'complexity':
              actionResult = await aiActions.rate(widget.task.id);
              break;
            case 'entities':
              actionResult = await aiActions.extract(widget.task.id);
              break;
            case 'duplicates':
              actionResult = await aiActions.checkDuplicates(widget.task.id);
              break;
            case 'remind':
              actionResult = await aiActions.remind(widget.task.id);
              break;
            case 'email':
              actionResult = await aiActions.email(widget.task.id);
              break;
            case 'calendar':
              actionResult = await aiActions.invite(widget.task.id);
              break;
          }
        } catch (e) {
          errorMessage = e.toString();
          rethrow;
        }
      },
      onRevert: () {
        // TODO: Implement revert logic per action type
        // For now, refresh to get server state
        ref.invalidate(tasksFetchProvider);
      },
    );

    if (!mounted) return;

    // Handle dialog result
    switch (result) {
      case AICookingResult.completed:
        _handleActionCompleted(action, actionResult);
        break;
      case AICookingResult.stopped:
        _showSnackBar('Action cancelled');
        break;
      case AICookingResult.timeout:
      case AICookingResult.background:
        _showSnackBar('Running in background...');
        break;
      case AICookingResult.error:
        _showSnackBar('Error: ${errorMessage ?? "Unknown error"}');
        break;
    }
  }

  void _handleActionCompleted(String action, dynamic result) {
    switch (action) {
      case 'decompose':
        // No message needed, subtasks appear automatically
        break;
      case 'complexity':
        if (result != null) {
          _showSnackBar('Complexity: ${result.complexity}/10');
        }
        break;
      case 'entities':
        // No message needed, chips appear automatically
        break;
      case 'duplicates':
        if (result != null && result.duplicates.isNotEmpty) {
          _showDuplicatesDialog(result.duplicates.cast<Task>(), result.reason);
        } else {
          _showNoSimilarTasksDialog();
        }
        break;
      case 'remind':
        if (result != null) {
          _showSnackBar('Reminder: ${result.reason}');
        }
        break;
      case 'email':
        if (result != null) {
          _showDraftDialog(result.draft);
        }
        break;
      case 'calendar':
        if (result != null) {
          _showDraftDialog(result.draft);
        }
        break;
    }
  }

  String _getActionDisplayName(String action) {
    switch (action) {
      case 'decompose':
        return 'Creating subtasks';
      case 'complexity':
        return 'Analyzing complexity';
      case 'entities':
        return 'Extracting entities';
      case 'duplicates':
        return 'Checking for duplicates';
      case 'remind':
        return 'Setting reminder';
      case 'email':
        return 'Drafting email';
      case 'calendar':
        return 'Creating calendar invite';
      default:
        return 'Processing';
    }
  }

  void _showOfflineTooltip() {
    final colors = context.flowColors;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.wifi_off_rounded, size: 18, color: colors.surface),
            const SizedBox(width: 8),
            const Text('You seem to be offline'),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        backgroundColor: colors.textSecondary,
      ),
    );
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

  void _showDuplicatesDialog(List<Task> duplicates, String? reason) {
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (dialogContext) => _SimilarTasksDialog(
        currentTask: widget.task,
        similarTasks: duplicates,
        reason: reason,
        onResolveDuplicate: () async {
          final aiActions = ref.read(aiActionsProvider);
          await aiActions.resolveDuplicate(widget.task.id);
          _showSnackBar('Marked as not duplicate');
        },
        onDeleteTask: (taskId) async {
          final actions = ref.read(taskActionsProvider);
          await actions.delete(taskId);
        },
      ),
    );
  }

  void _showNoSimilarTasksDialog() {
    if (!mounted) return;
    final colors = context.flowColors;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Similar Tasks'),
        content: Row(
          children: [
            Icon(Icons.check_circle_outline, color: colors.success, size: 24),
            const SizedBox(width: 12),
            const Text('No similar tasks found'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
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

  String _formatDueDate(DateTime date, bool hasDueTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dateOnly = DateTime(date.year, date.month, date.day);

    String dateStr;
    if (dateOnly == today) {
      dateStr = 'Today';
    } else if (dateOnly == today.add(const Duration(days: 1))) {
      dateStr = 'Tomorrow';
    } else if (dateOnly == today.subtract(const Duration(days: 1))) {
      dateStr = 'Yesterday';
    } else {
      dateStr = DateFormat('MMM d, yyyy').format(date);
    }

    // Add time only if hasDueTime flag is set (authoritative source)
    // Don't use date.hour/minute fallback as timezone conversion can make
    // midnight UTC appear as non-midnight local time
    if (hasDueTime) {
      final timeStr = DateFormat('h:mm a').format(date);
      return '$dateStr, $timeStr';
    }

    return dateStr;
  }

  String _formatDateTime(DateTime dt) {
    return DateFormat('MMM d, yyyy \'at\' h:mm a').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    // Watch the task from provider to get live updates
    final task = ref.watch(selectedTaskProvider) ?? widget.task;
    // Watch online status for AI buttons
    final isOnline = ref.watch(isOnlineProvider);

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
                    isOffline: !isOnline,
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
                  color: widget.localDueDate != null ? colors.primary : colors.textSecondary,
                ),
                onPressed: () async {
                  final taskId = task.id; // Capture task ID before async gap
                  final date = await TaskDateTimePicker.show(
                    context,
                    initialDate: widget.localDueDate,
                    hasTime: task.hasDueTime,
                    onClear: () async {
                      // Update parent's local state immediately
                      widget.onDateChanged(null);
                      // Then update the store with clearDueAt flag
                      final actions = ref.read(taskActionsProvider);
                      await actions.update(taskId, clearDueAt: true);
                    },
                  );
                  if (date != null && mounted) {
                    // Update parent's local state immediately for instant feedback
                    widget.onDateChanged(date);
                    // Then update the store (will sync in background)
                    final actions = ref.read(taskActionsProvider);
                    // Extract time if set (non-midnight means time was selected)
                    final hasTime = date.hour != 0 || date.minute != 0;
                    await actions.update(taskId, dueAt: date, hasDueTime: hasTime);
                  }
                },
                tooltip: widget.localDueDate != null ? _formatDueDate(widget.localDueDate!, task.hasDueTime) : 'Due Date',
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

              // More options (with timestamps)
              PopupMenuButton<String>(
                icon: Icon(Icons.more_horiz, color: colors.textSecondary, size: 20),
                padding: EdgeInsets.zero,
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
  final bool isOffline;
  final VoidCallback? onTap;

  const _AIActionText({
    required this.action,
    required this.isLoading,
    this.isOffline = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    // Apply blur/opacity when offline
    final effectiveOpacity = isOffline ? 0.4 : 1.0;

    return Opacity(
      opacity: effectiveOpacity,
      child: InkWell(
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
                    // Offline indicator
                    if (isOffline)
                      Positioned(
                        bottom: -2,
                        right: -4,
                        child: Icon(
                          Icons.wifi_off_rounded,
                          size: 10,
                          color: colors.textTertiary,
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
      ),
    );
  }
}

/// Subtasks section - displays child tasks with inline add
class _SubtasksSection extends ConsumerStatefulWidget {
  final String taskId;
  final Task parentTask;

  const _SubtasksSection({required this.taskId, required this.parentTask});

  @override
  ConsumerState<_SubtasksSection> createState() => _SubtasksSectionState();
}

class _SubtasksSectionState extends ConsumerState<_SubtasksSection> {
  String? _newSubtaskId; // ID of newly created subtask to auto-focus
  List<Task>? _optimisticSubtasks; // Local state for optimistic reordering

  Future<void> _addSubtask() async {
    try {
      final actions = ref.read(taskActionsProvider);
      // Create subtask with empty title - will show placeholder in text field
      final task = await actions.create(title: '', parentId: widget.taskId);
      ref.invalidate(subtasksProvider(widget.taskId));
      // Set the new subtask ID to trigger auto-edit
      setState(() => _newSubtaskId = task.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add subtask: $e')),
        );
      }
    }
  }

  Future<void> _onReorder(int oldIndex, int newIndex, List<Task> subtasks) async {
    // Adjust newIndex when moving down (Flutter's ReorderableListView behavior)
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }

    if (oldIndex == newIndex) return;

    // Get only incomplete subtasks (completed are at the bottom and not reorderable)
    final incompleteSubtasks = subtasks.where((t) => !t.isCompleted).toList();
    final completedSubtasks = subtasks.where((t) => t.isCompleted).toList();

    // Create new order by moving the item
    final reorderedIncomplete = List<Task>.from(incompleteSubtasks);
    final item = reorderedIncomplete.removeAt(oldIndex);
    reorderedIncomplete.insert(newIndex, item);

    // Optimistically update UI immediately
    setState(() {
      _optimisticSubtasks = [...reorderedIncomplete, ...completedSubtasks];
    });

    // Get the IDs in new order
    final taskIds = reorderedIncomplete.map((t) => t.id).toList();

    // Call the API to persist the new order (in background)
    try {
      final actions = ref.read(taskActionsProvider);
      await actions.reorderSubtasks(widget.taskId, taskIds);
      // Clear optimistic state after successful sync
      if (mounted) {
        setState(() => _optimisticSubtasks = null);
      }
    } catch (e) {
      // Revert optimistic update on error
      if (mounted) {
        setState(() => _optimisticSubtasks = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to reorder: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final serverSubtasks = ref.watch(subtasksProvider(widget.taskId));
    // Use optimistic state if available, otherwise use server state
    final subtasks = _optimisticSubtasks ?? serverSubtasks;

    final completed = subtasks.where((t) => t.isCompleted).length;
    final total = subtasks.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header (only show if there are subtasks)
        if (subtasks.isNotEmpty) ...[
          Row(
            children: [
              Icon(Icons.checklist_rounded, size: 16, color: colors.textTertiary),
              const SizedBox(width: 6),
              Text(
                'Subtasks',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: colors.textTertiary,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '($completed/$total)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: colors.textTertiary.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        // Subtask items with reorderable list
        if (subtasks.isNotEmpty)
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: subtasks.length,
            onReorder: (oldIndex, newIndex) => _onReorder(oldIndex, newIndex, subtasks),
            proxyDecorator: (child, index, animation) {
              return AnimatedBuilder(
                animation: animation,
                builder: (context, child) {
                  final elevation = Tween<double>(begin: 0, end: 4).animate(animation).value;
                  return Material(
                    elevation: elevation,
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(8),
                    child: child,
                  );
                },
                child: child,
              );
            },
            itemBuilder: (context, index) {
              final subtask = subtasks[index];
              final isLast = index == subtasks.length - 1;
              return _SubtaskItem(
                key: ValueKey(subtask.id),
                subtask: subtask,
                parentTask: widget.parentTask,
                index: index,
                autoFocus: subtask.id == _newSubtaskId,
                onEditComplete: () {
                  if (_newSubtaskId == subtask.id) {
                    setState(() => _newSubtaskId = null);
                  }
                },
                onSubmitAndContinue: isLast ? _addSubtask : null,
              );
            },
          ),
        // Add subtask button (always visible)
        Padding(
          padding: EdgeInsets.only(top: subtasks.isEmpty ? 0 : 8),
          child: InkWell(
            onTap: _addSubtask,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Icon(
                      Icons.add_rounded,
                      size: 18,
                      color: colors.textTertiary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Add a subtask...',
                    style: TextStyle(
                      fontSize: 14,
                      color: colors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Individual subtask item with checkbox - inline editable on tap
class _SubtaskItem extends ConsumerStatefulWidget {
  final Task subtask;
  final Task parentTask; // Parent task for confirmation dialog
  final int index; // Index for reordering
  final bool autoFocus;
  final VoidCallback? onEditComplete;
  final VoidCallback? onSubmitAndContinue; // Called when Enter pressed on last item

  const _SubtaskItem({
    super.key,
    required this.subtask,
    required this.parentTask,
    required this.index,
    this.autoFocus = false,
    this.onEditComplete,
    this.onSubmitAndContinue,
  });

  @override
  ConsumerState<_SubtaskItem> createState() => _SubtaskItemState();
}

class _SubtaskItemState extends ConsumerState<_SubtaskItem> {
  bool _isEditing = false;
  bool _isHovering = false;
  late TextEditingController _controller;
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // If title is empty, start with empty text (placeholder will show)
    _controller = TextEditingController(text: widget.subtask.title);
    _focusNode.addListener(_onFocusChange);
    // Auto-start editing if requested (or if title is empty)
    if (widget.autoFocus || widget.subtask.title.isEmpty) {
      _isEditing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusNode.requestFocus();
        // Only select all if there's text
        if (_controller.text.isNotEmpty) {
          _controller.selection = TextSelection(
            baseOffset: 0,
            extentOffset: _controller.text.length,
          );
        }
      });
    }
  }

  @override
  void didUpdateWidget(_SubtaskItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.subtask.title != widget.subtask.title && !_isEditing) {
      _controller.text = widget.subtask.title;
    }
    // Handle autoFocus changing to true
    if (widget.autoFocus && !oldWidget.autoFocus && !_isEditing) {
      _startEditing();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus && _isEditing) {
      _saveAndExit();
    }
  }

  void _startEditing() {
    setState(() => _isEditing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      // Select all text for easy replacement
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    });
  }

  Future<void> _saveAndExit({bool continueToNext = false}) async {
    final newTitle = _controller.text.trim();
    final actions = ref.read(taskActionsProvider);

    if (newTitle.isEmpty) {
      // Delete subtask if title is empty
      await actions.update(widget.subtask.id, status: 'cancelled');
      // Refresh subtasks list
      if (widget.subtask.parentId != null) {
        ref.invalidate(subtasksProvider(widget.subtask.parentId!));
      }
    } else if (newTitle != widget.subtask.title) {
      // Update title if changed
      await actions.update(widget.subtask.id, title: newTitle);
      // Refresh subtasks list
      if (widget.subtask.parentId != null) {
        ref.invalidate(subtasksProvider(widget.subtask.parentId!));
      }
    }

    if (mounted) {
      setState(() => _isEditing = false);
      widget.onEditComplete?.call();
      // If Enter was pressed on last item, create new subtask
      if (continueToNext && newTitle.isNotEmpty && widget.onSubmitAndContinue != null) {
        widget.onSubmitAndContinue!();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final isCompleted = widget.subtask.isCompleted;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle - only visible on hover
            AnimatedOpacity(
              opacity: _isHovering ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 150),
              child: ReorderableDragStartListener(
                index: widget.index,
                child: MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(
                      Icons.drag_indicator_rounded,
                      size: 18,
                      color: colors.textTertiary.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
            width: 24,
            height: 24,
            child: Checkbox(
              value: isCompleted,
              onChanged: (value) async {
                final actions = ref.read(taskActionsProvider);
                if (value == true) {
                  await actions.complete(widget.subtask.id);
                } else {
                  await actions.uncomplete(widget.subtask.id);
                }
                // Refresh subtasks
                ref.invalidate(subtasksProvider(widget.subtask.parentId!));
              },
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _isEditing
                ? TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    style: TextStyle(
                      fontSize: 14,
                      color: colors.textPrimary,
                    ),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 2),
                      hintText: 'New subtask',
                      hintStyle: TextStyle(
                        fontSize: 14,
                        color: colors.textTertiary,
                      ),
                    ),
                    onSubmitted: (_) => _saveAndExit(continueToNext: true),
                  )
                : GestureDetector(
                    onTap: _startEditing,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        widget.subtask.title,
                        style: TextStyle(
                          fontSize: 14,
                          color: isCompleted ? colors.textTertiary : colors.textPrimary,
                          decoration: isCompleted ? TextDecoration.lineThrough : null,
                        ),
                      ),
                    ),
                  ),
          ),
          // More options menu
          SizedBox(
            width: 24,
            height: 24,
            child: PopupMenuButton<String>(
              padding: EdgeInsets.zero,
              iconSize: 16,
              icon: Icon(
                Icons.more_horiz_rounded,
                color: colors.textTertiary.withValues(alpha: 0.5),
              ),
              tooltip: 'More options',
              offset: const Offset(0, 24),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              color: colors.surface,
              onSelected: (value) {
                if (value == 'delete') {
                  _deleteSubtask();
                } else if (value == 'move_to_main') {
                  _moveToMainList();
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem<String>(
                  value: 'move_to_main',
                  child: Row(
                    children: [
                      Icon(Icons.arrow_upward_rounded, size: 16, color: colors.textSecondary),
                      const SizedBox(width: 8),
                      Text(
                        'Move to main list',
                        style: TextStyle(fontSize: 13, color: colors.textPrimary),
                      ),
                    ],
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline_rounded, size: 16, color: colors.error),
                      const SizedBox(width: 8),
                      Text(
                        'Delete',
                        style: TextStyle(fontSize: 13, color: colors.error),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  Future<void> _deleteSubtask() async {
    final actions = ref.read(taskActionsProvider);
    await actions.update(widget.subtask.id, status: 'cancelled');
    if (widget.subtask.parentId != null) {
      ref.invalidate(subtasksProvider(widget.subtask.parentId!));
    }
  }

  Future<void> _moveToMainList() async {
    final colors = context.flowColors;

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Move to main list?'),
        content: RichText(
          text: TextSpan(
            style: TextStyle(fontSize: 14, color: colors.textPrimary),
            children: [
              const TextSpan(text: 'You\'re moving task '),
              TextSpan(
                text: '"${widget.subtask.title}"',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const TextSpan(text: ' to the main list. This task will no longer be a subtask of '),
              TextSpan(
                text: '"${widget.parentTask.displayTitle}"',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const TextSpan(text: '.\n\nDo you confirm?'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Move'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final actions = ref.read(taskActionsProvider);
      // Set parentId to empty string to remove parent (make it a root task)
      await actions.update(widget.subtask.id, parentId: '');

      // Refresh subtasks list
      if (widget.subtask.parentId != null) {
        ref.invalidate(subtasksProvider(widget.subtask.parentId!));
      }
      // Refresh main task list
      ref.invalidate(tasksFetchProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Moved "${widget.subtask.title}" to main list')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to move: $e')),
        );
      }
    }
  }
}

/// Entity chip with popup for task detail panel
class _EntityChipWithPopup extends StatelessWidget {
  final AIEntity entity;
  final String taskId;
  final VoidCallback onNavigateToSmartList;
  final VoidCallback onRemoveEntity;

  const _EntityChipWithPopup({
    required this.entity,
    required this.taskId,
    required this.onNavigateToSmartList,
    required this.onRemoveEntity,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final chipColors = _getEntityColors(entity.type, colors);

    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      offset: const Offset(0, 30),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      color: colors.surface,
      onSelected: (value) {
        if (value == 'view_all') {
          onNavigateToSmartList();
        } else if (value == 'remove') {
          onRemoveEntity();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(chipColors.icon, size: 16, color: chipColors.foreground),
                  const SizedBox(width: 8),
                  Text(
                    _getTypeLabel(entity.type),
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.textTertiary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                entity.value,
                style: TextStyle(
                  fontSize: 14,
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'view_all',
          child: Row(
            children: [
              Icon(Icons.list, size: 16, color: colors.textSecondary),
              const SizedBox(width: 8),
              Text(
                'View all tasks',
                style: TextStyle(
                  fontSize: 13,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'remove',
          child: Row(
            children: [
              Icon(Icons.remove_circle_outline, size: 16, color: colors.error),
              const SizedBox(width: 8),
              Text(
                'Remove this chip',
                style: TextStyle(
                  fontSize: 13,
                  color: colors.error,
                ),
              ),
            ],
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: chipColors.background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: chipColors.border, width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(chipColors.icon, size: 12, color: chipColors.foreground),
            const SizedBox(width: 4),
            Text(
              entity.value,
              style: TextStyle(
                fontSize: 12,
                color: chipColors.foreground,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getTypeLabel(String type) {
    switch (type) {
      case 'person':
        return 'Person';
      case 'location':
        return 'Location';
      case 'organization':
        return 'Organization';
      default:
        return type;
    }
  }

  _EntityChipColors _getEntityColors(String type, FlowColorScheme colors) {
    switch (type) {
      case 'person':
        return _EntityChipColors(
          background: const Color(0xFF3B82F6).withOpacity(0.1),
          foreground: const Color(0xFF3B82F6),
          border: const Color(0xFF3B82F6).withOpacity(0.3),
          icon: Icons.person_outline,
        );
      case 'location':
      case 'place': // Normalize place to location
        return _EntityChipColors(
          background: const Color(0xFF10B981).withOpacity(0.1),
          foreground: const Color(0xFF10B981),
          border: const Color(0xFF10B981).withOpacity(0.3),
          icon: Icons.place, // Google Maps-like icon
        );
      case 'organization':
        return _EntityChipColors(
          background: const Color(0xFF8B5CF6).withOpacity(0.1),
          foreground: const Color(0xFF8B5CF6),
          border: const Color(0xFF8B5CF6).withOpacity(0.3),
          icon: Icons.business_outlined,
        );
      default:
        return _EntityChipColors(
          background: colors.textTertiary.withOpacity(0.1),
          foreground: colors.textSecondary,
          border: colors.textTertiary.withOpacity(0.3),
          icon: Icons.label_outline,
        );
    }
  }
}

class _EntityChipColors {
  final Color background;
  final Color foreground;
  final Color border;
  final IconData icon;

  const _EntityChipColors({
    required this.background,
    required this.foreground,
    required this.border,
    required this.icon,
  });
}

/// Dialog for showing similar tasks with preview and delete functionality
class _SimilarTasksDialog extends StatefulWidget {
  final Task currentTask;
  final List<Task> similarTasks;
  final String? reason;
  final VoidCallback onResolveDuplicate;
  final Future<void> Function(String taskId) onDeleteTask;

  const _SimilarTasksDialog({
    required this.currentTask,
    required this.similarTasks,
    this.reason,
    required this.onResolveDuplicate,
    required this.onDeleteTask,
  });

  @override
  State<_SimilarTasksDialog> createState() => _SimilarTasksDialogState();
}

class _SimilarTasksDialogState extends State<_SimilarTasksDialog> {
  Task? _previewTask;
  final Set<String> _deletedTaskIds = {};
  final Set<String> _deletingTaskIds = {};
  bool _currentTaskDeleted = false;
  bool _currentTaskDeleting = false;

  List<Task> get _activeTasks => widget.similarTasks
      .where((t) => !_deletedTaskIds.contains(t.id))
      .toList();

  int get _totalActiveCount => _activeTasks.length + (_currentTaskDeleted ? 0 : 1);

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;

    // If previewing a task, show preview mode
    if (_previewTask != null) {
      return _buildPreviewMode(colors);
    }

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: FlowSpacing.dialogMaxWidth),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_activeTasks.length} Similar Task${_activeTasks.length == 1 ? '' : 's'} Found',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.reason != null && widget.reason!.isNotEmpty) ...[
                        Text(
                          widget.reason!,
                          style: TextStyle(
                            fontSize: 13,
                            color: colors.textTertiary,
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      // Current task with "This Task" badge
                      _buildCurrentTaskItem(colors),
                      const SizedBox(height: 12),
                      // Divider
                      Row(
                        children: [
                          Expanded(child: Divider(color: colors.divider)),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              'Similar to',
                              style: TextStyle(
                                fontSize: 11,
                                color: colors.textTertiary,
                              ),
                            ),
                          ),
                          Expanded(child: Divider(color: colors.divider)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Similar tasks list
                      ...widget.similarTasks.map((task) => _buildSimilarTaskItem(task, colors)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Only show Keep Both/All if at least 2 tasks remain
                  if (_totalActiveCount >= 2)
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        widget.onResolveDuplicate();
                      },
                      child: Text(_totalActiveCount >= 3 ? 'Keep All' : 'Keep Both'),
                    ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentTaskItem(FlowColorScheme colors) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      opacity: _currentTaskDeleted ? 0.4 : 1.0,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _currentTaskDeleted
              ? colors.surface.withOpacity(0.5)
              : colors.primary.withOpacity(0.05),
          border: Border.all(
            color: _currentTaskDeleted
                ? colors.divider.withOpacity(0.5)
                : colors.primary.withOpacity(0.3),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _currentTaskDeleted ? colors.textTertiary : colors.primary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'This Task',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.currentTask.title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      decoration: _currentTaskDeleted ? TextDecoration.lineThrough : null,
                      color: _currentTaskDeleted ? colors.textTertiary : null,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (widget.currentTask.dueAt != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.event_outlined, size: 12, color: colors.textTertiary),
                        const SizedBox(width: 4),
                        Text(
                          DateFormat('MMM d').format(widget.currentTask.dueAt!),
                          style: TextStyle(fontSize: 11, color: colors.textTertiary),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (!_currentTaskDeleted) ...[
              // Delete button for current task
              IconButton(
                icon: _currentTaskDeleting
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: colors.error),
                      )
                    : Icon(Icons.delete_outline, size: 20, color: colors.error),
                onPressed: _currentTaskDeleting ? null : _deleteCurrentTask,
                tooltip: 'Delete this task',
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                padding: EdgeInsets.zero,
              ),
            ] else ...[
              Text(
                'Deleted',
                style: TextStyle(fontSize: 11, color: colors.textTertiary, fontStyle: FontStyle.italic),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _deleteCurrentTask() async {
    setState(() => _currentTaskDeleting = true);

    try {
      await widget.onDeleteTask(widget.currentTask.id);
      if (mounted) {
        setState(() {
          _currentTaskDeleted = true;
          _currentTaskDeleting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _currentTaskDeleting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: $e')),
        );
      }
    }
  }

  Widget _buildSimilarTaskItem(Task task, FlowColorScheme colors) {
    final isDeleted = _deletedTaskIds.contains(task.id);
    final isDeleting = _deletingTaskIds.contains(task.id);

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      opacity: isDeleted ? 0.4 : 1.0,
      child: Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          border: Border.all(color: isDeleted ? colors.divider.withOpacity(0.5) : colors.divider),
          borderRadius: BorderRadius.circular(8),
          color: isDeleted ? colors.surface.withOpacity(0.5) : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      decoration: isDeleted ? TextDecoration.lineThrough : null,
                      color: isDeleted ? colors.textTertiary : null,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (task.dueAt != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.event_outlined, size: 12, color: colors.textTertiary),
                        const SizedBox(width: 4),
                        Text(
                          DateFormat('MMM d').format(task.dueAt!),
                          style: TextStyle(fontSize: 11, color: colors.textTertiary),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (!isDeleted) ...[
              // View details button
              IconButton(
                icon: Icon(Icons.chevron_right, size: 20, color: colors.textTertiary),
                onPressed: () => setState(() => _previewTask = task),
                tooltip: 'View details',
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                padding: EdgeInsets.zero,
              ),
              // Delete button
              IconButton(
                icon: isDeleting
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: colors.error),
                      )
                    : Icon(Icons.delete_outline, size: 20, color: colors.error),
                onPressed: isDeleting ? null : () => _deleteTask(task.id),
                tooltip: 'Delete this task',
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                padding: EdgeInsets.zero,
              ),
            ] else ...[
              Text(
                'Deleted',
                style: TextStyle(fontSize: 11, color: colors.textTertiary, fontStyle: FontStyle.italic),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewMode(FlowColorScheme colors) {
    final task = _previewTask!;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: FlowSpacing.dialogMaxWidth),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => setState(() => _previewTask = null),
                    tooltip: 'Back to list',
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    padding: EdgeInsets.zero,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('Task Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
                ],
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Title
                      Text(
                        task.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Description
                      if (task.description != null && task.description!.isNotEmpty) ...[
                        Text(
                          'Description',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colors.textTertiary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          task.description!,
                          style: const TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 16),
                      ],
                      // Due date
                      if (task.dueAt != null) ...[
                        Row(
                          children: [
                            Icon(Icons.event_outlined, size: 16, color: colors.textTertiary),
                            const SizedBox(width: 8),
                            Text(
                              'Due: ${DateFormat('MMM d, yyyy').format(task.dueAt!)}',
                              style: TextStyle(fontSize: 13, color: colors.textSecondary),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                      // Status
                      Row(
                        children: [
                          Icon(
                            task.isCompleted ? Icons.check_circle : Icons.radio_button_unchecked,
                            size: 16,
                            color: task.isCompleted ? Colors.green : colors.textTertiary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            task.isCompleted ? 'Completed' : 'Pending',
                            style: TextStyle(fontSize: 13, color: colors.textSecondary),
                          ),
                        ],
                      ),
                      // Created date
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.access_time, size: 16, color: colors.textTertiary),
                          const SizedBox(width: 8),
                          Text(
                            'Created: ${DateFormat('MMM d, yyyy').format(task.createdAt)}',
                            style: TextStyle(fontSize: 13, color: colors.textSecondary),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: colors.error),
                    onPressed: () async {
                      await _deleteTask(task.id);
                      if (mounted) setState(() => _previewTask = null);
                    },
                    child: const Text('Delete This Task'),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _previewTask = null),
                    child: const Text('Back'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteTask(String taskId) async {
    setState(() => _deletingTaskIds.add(taskId));

    try {
      await widget.onDeleteTask(taskId);
      if (mounted) {
        setState(() {
          _deletedTaskIds.add(taskId);
          _deletingTaskIds.remove(taskId);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _deletingTaskIds.remove(taskId));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: $e')),
        );
      }
    }
  }
}

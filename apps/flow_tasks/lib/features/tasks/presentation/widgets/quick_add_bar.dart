import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flow_tasks/core/constants/app_colors.dart';
import 'package:flow_tasks/core/constants/app_spacing.dart';
import 'package:flow_tasks/core/providers/providers.dart';
import 'package:flow_tasks/core/theme/flow_theme.dart';
import 'package:flow_tasks/features/tasks/presentation/widgets/hashtag_text_field.dart';

class QuickAddBar extends ConsumerStatefulWidget {
  const QuickAddBar({super.key});

  @override
  ConsumerState<QuickAddBar> createState() => _QuickAddBarState();
}

class _QuickAddBarState extends ConsumerState<QuickAddBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _hasFocus = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      setState(() => _hasFocus = _focusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit(String text) async {
    if (text.trim().isEmpty || _isSubmitting) return;

    setState(() => _isSubmitting = true);

    try {
      // Check if we're in a List or Smart List view (task won't appear there immediately)
      final inListView = ref.read(selectedListIdProvider) != null;
      final inSmartListView = ref.read(selectedSmartListProvider) != null;
      final shouldNavigateAway = inListView || inSmartListView;

      // Use optimistic task actions - instant UI update
      // Auto-add to "today" by setting due date to start of today (no specific time)
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final actions = ref.read(taskActionsProvider);
      final newTask = await actions.create(title: text.trim(), dueAt: today);

      _controller.clear();
      _focusNode.unfocus();

      // If created from List/Smart List view, navigate to Next 7 days to show the task
      if (shouldNavigateAway) {
        ref.read(selectedListIdProvider.notifier).state = null;
        ref.read(selectedSmartListProvider.notifier).state = null;
        ref.read(selectedSidebarIndexProvider.notifier).state = 1; // Next 7 days
      }

      // Open the task detail panel for the new task
      ref.read(selectedTaskIdProvider.notifier).state = newTask.id;
      ref.read(isNewlyCreatedTaskProvider.notifier).state = true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create task: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _hasFocus = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(FlowSpacing.radiusMd),
        boxShadow: _hasFocus ? null : FlowColors.cardShadowLight,
        border: Border.all(
          color: _hasFocus ? colors.primary : colors.border.withOpacity(0.5),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 16),
          Icon(
            Icons.add_rounded,
            color: _hasFocus ? colors.primary : colors.textTertiary,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: HashtagTextField(
              controller: _controller,
              focusNode: _focusNode,
              hintText: 'Add a task...',
              decoration: InputDecoration(
                hintText: 'Add a task...',
                hintStyle: TextStyle(color: colors.textPlaceholder),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                filled: false,
              ),
              onSubmitted: _handleSubmit,
            ),
          ),
          if (_controller.text.isNotEmpty && !_isSubmitting)
            IconButton(
              icon: Icon(
                Icons.send_rounded,
                color: colors.primary,
                size: 20,
              ),
              onPressed: () => _handleSubmit(_controller.text),
            ),
          if (_isSubmitting)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

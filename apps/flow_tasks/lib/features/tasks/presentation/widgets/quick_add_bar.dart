import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flow_tasks/core/constants/app_colors.dart';
import 'package:flow_tasks/core/constants/app_spacing.dart';
import 'package:flow_tasks/core/providers/providers.dart';
import 'package:flow_tasks/core/theme/flow_theme.dart';

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
      final service = ref.read(tasksServiceProvider);
      await service.create(title: text.trim());

      _controller.clear();
      _focusNode.unfocus();

      // Refresh tasks
      ref.invalidate(inboxTasksProvider);
      ref.invalidate(todayTasksProvider);
      ref.invalidate(tasksProvider);
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
      margin: EdgeInsets.symmetric(
        horizontal: _hasFocus ? 0 : 16,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(
          _hasFocus ? 0 : FlowSpacing.radiusMd,
        ),
        boxShadow: _hasFocus ? null : FlowColors.cardShadowLight,
        border: Border.all(
          color: _hasFocus ? colors.primary : colors.border.withOpacity(0.5),
          width: _hasFocus ? 2 : 1,
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
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              style: TextStyle(
                fontSize: 15,
                color: colors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'Add a task...',
                hintStyle: TextStyle(color: colors.textPlaceholder),
                border: InputBorder.none,
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

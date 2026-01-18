import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flow_models/flow_models.dart';
import 'package:flow_tasks/core/providers/providers.dart';
import 'package:flow_tasks/core/theme/flow_theme.dart';

/// TextField with hashtag autocomplete support (Bear-style #List/Sublist)
class HashtagTextField extends ConsumerStatefulWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String? hintText;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final bool autofocus;
  final int? maxLines;
  final InputDecoration? decoration;

  const HashtagTextField({
    super.key,
    required this.controller,
    this.focusNode,
    this.hintText,
    this.onSubmitted,
    this.onChanged,
    this.autofocus = false,
    this.maxLines = 1,
    this.decoration,
  });

  @override
  ConsumerState<HashtagTextField> createState() => _HashtagTextFieldState();
}

class _HashtagTextFieldState extends ConsumerState<HashtagTextField> {
  late FocusNode _focusNode;
  bool _showSuggestions = false;
  bool _autocompleteActivated = false; // Tracks if dropdown was ever triggered
  int? _hashtagStartIndex;
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _removeOverlay();
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  void _onTextChanged() {
    final text = widget.controller.text;
    final selection = widget.controller.selection;

    if (!selection.isValid || selection.start != selection.end) {
      _hideDropdown();
      return;
    }

    final cursorPos = selection.start;
    final textBeforeCursor = text.substring(0, cursorPos);

    // Find the last # before cursor
    final lastHashIndex = textBeforeCursor.lastIndexOf('#');

    if (lastHashIndex == -1) {
      _hideDropdown();
      return;
    }

    // Check if there's a space between # and cursor (means we've completed the tag)
    final textAfterHash = textBeforeCursor.substring(lastHashIndex + 1);
    if (textAfterHash.contains(' ')) {
      _hideDropdown();
      return;
    }

    // Extract the query (text after #)
    final query = textAfterHash;

    // Activation logic: require at least one char after # to initially trigger
    // But once triggered, keep showing even if backspaced to just #
    if (!_autocompleteActivated && query.isEmpty) {
      // Not yet activated and no query - don't show
      return;
    }

    // Activate on first character after #
    if (query.isNotEmpty && !_autocompleteActivated) {
      _autocompleteActivated = true;
    }

    // Update the provider
    ref.read(hashtagQueryProvider.notifier).state = query;
    _hashtagStartIndex = lastHashIndex;

    _showDropdown();
  }

  void _showDropdown() {
    if (_showSuggestions) return;
    setState(() => _showSuggestions = true);
    _showOverlay();
  }

  void _hideDropdown() {
    if (!_showSuggestions) return;
    setState(() => _showSuggestions = false);
    _removeOverlay();
    ref.read(hashtagQueryProvider.notifier).state = '';
    _hashtagStartIndex = null;
    _autocompleteActivated = false; // Reset activation state
  }

  void _showOverlay() {
    _removeOverlay();

    _overlayEntry = OverlayEntry(
      builder: (context) => _HashtagSuggestionsOverlay(
        link: _layerLink,
        onSelect: _onSuggestionSelected,
        onDismiss: _hideDropdown,
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _onSuggestionSelected(TaskList list) {
    if (_hashtagStartIndex == null) return;

    final text = widget.controller.text;
    final beforeHash = text.substring(0, _hashtagStartIndex!);
    final cursorPos = widget.controller.selection.start;
    final afterCursor = cursorPos < text.length ? text.substring(cursorPos) : '';

    // Insert the full path with a trailing space
    final newText = '$beforeHash#${list.fullPath} $afterCursor';
    widget.controller.text = newText;

    // Move cursor after the inserted tag
    final newCursorPos = beforeHash.length + 1 + list.fullPath.length + 1;
    widget.controller.selection = TextSelection.collapsed(offset: newCursorPos);

    _hideDropdown();
    widget.onChanged?.call(newText);
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextField(
        controller: widget.controller,
        focusNode: _focusNode,
        autofocus: widget.autofocus,
        maxLines: widget.maxLines,
        decoration: widget.decoration ??
            InputDecoration(
              hintText: widget.hintText,
              border: InputBorder.none,
            ),
        onSubmitted: widget.onSubmitted,
        onChanged: widget.onChanged,
      ),
    );
  }
}

class _HashtagSuggestionsOverlay extends ConsumerStatefulWidget {
  final LayerLink link;
  final ValueChanged<TaskList> onSelect;
  final VoidCallback onDismiss;

  const _HashtagSuggestionsOverlay({
    required this.link,
    required this.onSelect,
    required this.onDismiss,
  });

  @override
  ConsumerState<_HashtagSuggestionsOverlay> createState() =>
      _HashtagSuggestionsOverlayState();
}

class _HashtagSuggestionsOverlayState
    extends ConsumerState<_HashtagSuggestionsOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = ref.watch(hashtagSuggestionsProvider);
    final query = ref.watch(hashtagQueryProvider);
    final colors = context.flowColors;

    // Only show dropdown when there are matching suggestions
    // New lists are auto-created by the backend when the task is saved
    if (suggestions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Stack(
      children: [
        // Tap outside to dismiss
        Positioned.fill(
          child: GestureDetector(
            onTap: widget.onDismiss,
            behavior: HitTestBehavior.opaque,
            child: const SizedBox.expand(),
          ),
        ),
        // Animated suggestions dropdown - use UnconstrainedBox for proper positioning
        CompositedTransformFollower(
          link: widget.link,
          showWhenUnlinked: false,
          offset: const Offset(0, 44),
          targetAnchor: Alignment.bottomLeft,
          followerAnchor: Alignment.topLeft,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SlideTransition(
              position: _slideAnimation,
              child: Material(
                elevation: 0,
                color: Colors.transparent,
                child: Container(
                  width: 280,
                  constraints: const BoxConstraints(maxHeight: 260),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: colors.border.withOpacity(0.5),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.12),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Header when searching
                        if (query.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(color: colors.border.withOpacity(0.3)),
                              ),
                            ),
                            child: Text(
                              'Lists matching "#$query"',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: colors.textTertiary,
                              ),
                            ),
                          ),
                        // Scrollable list - only show existing lists as suggestions
                        // New lists are auto-created by the backend when the task is saved
                        if (suggestions.isNotEmpty)
                          Flexible(
                            child: ListView(
                              shrinkWrap: true,
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              children: suggestions.map((list) => _SuggestionTile(
                                list: list,
                                onTap: () => widget.onSelect(list),
                              )).toList(),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  final TaskList list;
  final VoidCallback onTap;

  const _SuggestionTile({
    required this.list,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final isSublist = list.depth > 0;
    final listColor = list.color != null
        ? _parseColor(list.color!)
        : colors.textSecondary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.only(
            left: isSublist ? 36.0 : 14.0,
            right: 14.0,
            top: 10.0,
            bottom: 10.0,
          ),
          child: Row(
            children: [
              // Icon with subtle background
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: listColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  isSublist
                      ? Icons.subdirectory_arrow_right_rounded
                      : Icons.tag_rounded,
                  size: 16,
                  color: listColor,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      list.name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: colors.textPrimary,
                      ),
                    ),
                    if (isSublist)
                      Text(
                        list.fullPath,
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.textTertiary,
                        ),
                      ),
                  ],
                ),
              ),
              // Task count badge
              if (list.taskCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: colors.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${list.taskCount}',
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.textTertiary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Color _parseColor(String color) {
    if (color.startsWith('#')) {
      return Color(int.parse(color.substring(1), radix: 16) + 0xFF000000);
    }
    return Colors.grey;
  }
}

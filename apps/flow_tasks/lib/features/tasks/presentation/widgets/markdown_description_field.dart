import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flow_models/flow_models.dart';
import 'package:flow_tasks/core/providers/providers.dart';
import 'package:flow_tasks/core/theme/flow_theme.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pasteboard/pasteboard.dart';

/// Live markdown TextEditingController that styles text in real-time
/// Key: ALL characters are preserved (no hiding), only styling changes
/// - Markers (**, *) shown in subtle gray
/// - Content styled appropriately (bold, italic)
/// - Hashtags styled in accent color
class LiveMarkdownController extends TextEditingController {
  final Color textColor;
  final Color markerColor;
  final Color hashtagColor;

  LiveMarkdownController({
    String? text,
    required this.textColor,
    required this.markerColor,
    required this.hashtagColor,
  }) : super(text: text);

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final text = this.text;
    if (text.isEmpty) {
      return TextSpan(text: '', style: style);
    }

    final baseStyle = style ?? const TextStyle();
    final spans = <InlineSpan>[];
    var currentIndex = 0;

    // Find all markdown patterns
    final patterns = _findPatterns(text);

    for (final pattern in patterns) {
      // Add plain text before this pattern
      if (pattern.start > currentIndex) {
        spans.add(TextSpan(
          text: text.substring(currentIndex, pattern.start),
          style: baseStyle,
        ));
      }

      // Add the pattern with appropriate styling
      switch (pattern.type) {
        case _PatternType.bold:
          // Opening **
          spans.add(TextSpan(
            text: '**',
            style: baseStyle.copyWith(color: markerColor),
          ));
          // Bold content
          spans.add(TextSpan(
            text: pattern.content,
            style: baseStyle.copyWith(fontWeight: FontWeight.bold),
          ));
          // Closing **
          spans.add(TextSpan(
            text: '**',
            style: baseStyle.copyWith(color: markerColor),
          ));
          break;

        case _PatternType.italic:
          // Opening *
          spans.add(TextSpan(
            text: '*',
            style: baseStyle.copyWith(color: markerColor),
          ));
          // Italic content
          spans.add(TextSpan(
            text: pattern.content,
            style: baseStyle.copyWith(fontStyle: FontStyle.italic),
          ));
          // Closing *
          spans.add(TextSpan(
            text: '*',
            style: baseStyle.copyWith(color: markerColor),
          ));
          break;

        case _PatternType.hashtag:
          // Hashtag in accent color
          spans.add(TextSpan(
            text: pattern.fullMatch,
            style: baseStyle.copyWith(color: hashtagColor),
          ));
          break;

        case _PatternType.image:
          // Image reference in muted color with icon indicator
          spans.add(TextSpan(
            text: pattern.fullMatch,
            style: baseStyle.copyWith(
              color: markerColor,
              backgroundColor: markerColor.withAlpha(30),
            ),
          ));
          break;
      }

      currentIndex = pattern.end;
    }

    // Add remaining text
    if (currentIndex < text.length) {
      spans.add(TextSpan(
        text: text.substring(currentIndex),
        style: baseStyle,
      ));
    }

    if (spans.isEmpty) {
      return TextSpan(text: text, style: baseStyle);
    }

    return TextSpan(children: spans, style: baseStyle);
  }

  List<_MarkdownPattern> _findPatterns(String text) {
    final patterns = <_MarkdownPattern>[];

    // Bold: **text** (must have content, non-greedy)
    final boldRegex = RegExp(r'\*\*([^*]+)\*\*');
    for (final match in boldRegex.allMatches(text)) {
      patterns.add(_MarkdownPattern(
        type: _PatternType.bold,
        start: match.start,
        end: match.end,
        content: match.group(1)!,
        fullMatch: match.group(0)!,
      ));
    }

    // Italic: *text* (not preceded/followed by *)
    final italicRegex = RegExp(r'(?<!\*)\*([^*]+)\*(?!\*)');
    for (final match in italicRegex.allMatches(text)) {
      // Check no overlap with bold
      final overlaps = patterns.any((p) =>
          (match.start >= p.start && match.start < p.end) ||
          (match.end > p.start && match.end <= p.end));
      if (!overlaps) {
        patterns.add(_MarkdownPattern(
          type: _PatternType.italic,
          start: match.start,
          end: match.end,
          content: match.group(1)!,
          fullMatch: match.group(0)!,
        ));
      }
    }

    // Hashtags: #word or #word/subword
    final hashtagRegex = RegExp(r'#[A-Za-z0-9_]+(?:/[A-Za-z0-9_]+)?');
    for (final match in hashtagRegex.allMatches(text)) {
      // Check no overlap
      final overlaps = patterns.any((p) =>
          (match.start >= p.start && match.start < p.end) ||
          (match.end > p.start && match.end <= p.end));
      if (!overlaps) {
        patterns.add(_MarkdownPattern(
          type: _PatternType.hashtag,
          start: match.start,
          end: match.end,
          content: match.group(0)!,
          fullMatch: match.group(0)!,
        ));
      }
    }

    // Image references: [img1], [img2], etc. or [img...]
    final imageRegex = RegExp(r'\[img(\d+|\.\.\.)\]');
    for (final match in imageRegex.allMatches(text)) {
      // Check no overlap
      final overlaps = patterns.any((p) =>
          (match.start >= p.start && match.start < p.end) ||
          (match.end > p.start && match.end <= p.end));
      if (!overlaps) {
        patterns.add(_MarkdownPattern(
          type: _PatternType.image,
          start: match.start,
          end: match.end,
          content: match.group(1)!, // The number or "..."
          fullMatch: match.group(0)!,
        ));
      }
    }

    // Sort by start position
    patterns.sort((a, b) => a.start.compareTo(b.start));
    return patterns;
  }
}

enum _PatternType { bold, italic, hashtag, image }

/// For matching in rendered body
enum _MatchType { hashtag, image }

class _SpecialMatch {
  final _MatchType type;
  final int start;
  final int end;
  final String content;
  final String id;

  _SpecialMatch({
    required this.type,
    required this.start,
    required this.end,
    required this.content,
    required this.id,
  });
}

class _MarkdownPattern {
  final _PatternType type;
  final int start;
  final int end;
  final String content;
  final String fullMatch;

  _MarkdownPattern({
    required this.type,
    required this.start,
    required this.end,
    required this.content,
    required this.fullMatch,
  });
}

/// Callback for image paste - returns the image index (1-based) after upload
typedef ImagePasteCallback = Future<int?> Function(Uint8List imageBytes, String mimeType);

/// Callback to get image URL by index (1-based)
typedef ImageUrlResolver = String? Function(int imageIndex);

/// Bear-style markdown description field with live rendering
class MarkdownDescriptionField extends ConsumerStatefulWidget {
  final String? initialValue;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onEditingComplete;
  final bool readOnly;
  /// Called when user pastes an image - should upload and return attachment ID
  final ImagePasteCallback? onImagePaste;
  /// Called to resolve [img-{id}] to actual image URL
  final ImageUrlResolver? imageUrlResolver;

  const MarkdownDescriptionField({
    super.key,
    this.initialValue,
    this.hintText = 'Add description...',
    this.onChanged,
    this.onEditingComplete,
    this.readOnly = false,
    this.onImagePaste,
    this.imageUrlResolver,
  });

  @override
  ConsumerState<MarkdownDescriptionField> createState() => _MarkdownDescriptionFieldState();
}

class _MarkdownDescriptionFieldState extends ConsumerState<MarkdownDescriptionField> {
  LiveMarkdownController? _controller;
  late FocusNode _focusNode;
  bool _isEditing = false;
  bool _isToolbarInteraction = false;
  TextSelection? _lastSelection;

  // Hashtag autocomplete state
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  bool _showSuggestions = false;
  bool _isSelectingHashtag = false; // Prevents focus loss from clearing state
  int? _hashtagStartIndex;
  int? _hashtagEndIndex; // Where the cursor was when typing the hashtag
  String _currentHashtagQuery = '';
  Offset _hashtagOffset = Offset.zero; // Position for dropdown
  int _dropdownSelectedIndex = 0; // Keyboard navigation index

  // Image paste state
  bool _isUploadingImage = false;
  String? _uploadingPlaceholder; // Temporary placeholder while uploading

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller == null) {
      final colors = context.flowColors;
      _controller = LiveMarkdownController(
        text: widget.initialValue ?? '',
        textColor: colors.textSecondary,
        markerColor: colors.textTertiary.withAlpha(120),
        hashtagColor: colors.primary,
      );
      _controller!.addListener(_onSelectionChanged);
      _controller!.addListener(_onTextChangedForHashtag);
    }
  }

  void _onSelectionChanged() {
    final selection = _controller!.selection;
    if (selection.isValid && !selection.isCollapsed) {
      _lastSelection = selection;
    }
    // Trigger rebuild for cursor-position-aware styling
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant MarkdownDescriptionField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue && !_isEditing) {
      _controller?.text = widget.initialValue ?? '';
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _controller?.removeListener(_onSelectionChanged);
    _controller?.removeListener(_onTextChangedForHashtag);
    _removeOverlay();
    _focusNode.dispose();
    _controller?.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus && _isToolbarInteraction) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
      return;
    }

    // Don't clear state if we're in the middle of selecting a hashtag
    if (!_focusNode.hasFocus && _isSelectingHashtag) {
      return;
    }

    setState(() => _isEditing = _focusNode.hasFocus);
    if (!_focusNode.hasFocus) {
      _hideHashtagDropdown();
      widget.onEditingComplete?.call();
    }
  }

  // Hashtag autocomplete methods
  void _onTextChangedForHashtag() {
    final text = _controller!.text;
    final selection = _controller!.selection;

    if (!selection.isValid || selection.start != selection.end) {
      _hideHashtagDropdown();
      return;
    }

    final cursorPos = selection.start;
    final textBeforeCursor = text.substring(0, cursorPos);

    // Find the last # before cursor
    final lastHashIndex = textBeforeCursor.lastIndexOf('#');

    if (lastHashIndex == -1) {
      _hideHashtagDropdown();
      return;
    }

    // Check if there's a space/newline between # and cursor
    final textAfterHash = textBeforeCursor.substring(lastHashIndex + 1);
    if (textAfterHash.contains(' ') || textAfterHash.contains('\n')) {
      _hideHashtagDropdown();
      return;
    }

    // Extract query and update
    final query = textAfterHash;
    _currentHashtagQuery = query;
    _hashtagStartIndex = lastHashIndex;
    _hashtagEndIndex = cursorPos; // Track where cursor is now
    ref.read(hashtagQueryProvider.notifier).state = query;

    // Calculate position of the hashtag for dropdown placement
    _calculateHashtagPosition(lastHashIndex);

    // Show dropdown after first char typed
    if (query.isNotEmpty) {
      _showHashtagDropdown();
    }
  }

  void _calculateHashtagPosition(int hashIndex) {
    final text = _controller!.text;
    if (text.isEmpty || !mounted) return;

    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    // Use TextPainter to find position of hashtag
    const textStyle = TextStyle(fontSize: 15, height: 1.5);
    final textPainter = TextPainter(
      text: TextSpan(text: text.substring(0, hashIndex), style: textStyle),
      textDirection: TextDirection.ltr,
      maxLines: null,
    );

    final maxWidth = renderBox.size.width;
    textPainter.layout(maxWidth: maxWidth);

    // Get the offset at the hashtag position
    final pos = textPainter.size;
    // Calculate x position (end of text before #)
    final lastLineWidth = _getLastLineWidth(textPainter, text.substring(0, hashIndex), maxWidth);

    _hashtagOffset = Offset(lastLineWidth, pos.height);
  }

  double _getLastLineWidth(TextPainter painter, String text, double maxWidth) {
    if (text.isEmpty) return 0;

    final metrics = painter.computeLineMetrics();
    if (metrics.isEmpty) return 0;

    // Get the width of the last line
    return metrics.last.width;
  }

  void _showHashtagDropdown() {
    if (_showSuggestions) {
      // Just update the overlay
      _overlayEntry?.markNeedsBuild();
      return;
    }
    setState(() => _showSuggestions = true);
    _showOverlay();
  }

  void _hideHashtagDropdown() {
    if (!_showSuggestions) return;
    setState(() => _showSuggestions = false);
    _removeOverlay();
    ref.read(hashtagQueryProvider.notifier).state = '';
    _hashtagStartIndex = null;
    _hashtagEndIndex = null;
    _currentHashtagQuery = '';
    _dropdownSelectedIndex = 0;
  }

  void _showOverlay() {
    _removeOverlay();
    _dropdownSelectedIndex = 0; // Reset selection when showing new dropdown

    _overlayEntry = OverlayEntry(
      builder: (context) => _BearHashtagDropdown(
        link: _layerLink,
        offset: _hashtagOffset,
        query: _currentHashtagQuery,
        selectedIndex: _dropdownSelectedIndex,
        onSelect: _onHashtagSelected,
        onDismiss: _hideHashtagDropdown,
        onStartSelection: _startHashtagSelection,
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry?.dispose();
    _overlayEntry = null;
  }

  void _onHashtagSelected(TaskList list) {
    if (_hashtagStartIndex == null || _hashtagEndIndex == null) {
      _isSelectingHashtag = false;
      return;
    }

    final text = _controller!.text;
    final startIdx = _hashtagStartIndex!;
    final endIdx = _hashtagEndIndex!.clamp(startIdx, text.length);

    // Replace from # to current cursor position with the selected hashtag
    final beforeHash = text.substring(0, startIdx);
    final afterCursor = endIdx < text.length ? text.substring(endIdx) : '';

    final newText = '$beforeHash#${list.fullPath} $afterCursor';

    // Update text and cursor position
    final newCursorPos = startIdx + 1 + list.fullPath.length + 1;

    _controller!.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCursorPos),
    );

    _hideHashtagDropdown();
    _isSelectingHashtag = false;
    widget.onChanged?.call(newText);

    // Restore focus to the text field
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
        setState(() => _isEditing = true);
      }
    });
  }

  void _startHashtagSelection() {
    _isSelectingHashtag = true;
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    // Handle dropdown navigation when suggestions are showing
    if (_showSuggestions) {
      final suggestions = ref.read(hashtagSuggestionsProvider);
      if (suggestions.isNotEmpty) {
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          setState(() {
            _dropdownSelectedIndex = (_dropdownSelectedIndex + 1) % suggestions.length;
          });
          _overlayEntry?.markNeedsBuild();
          return;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          setState(() {
            _dropdownSelectedIndex = (_dropdownSelectedIndex - 1 + suggestions.length) % suggestions.length;
          });
          _overlayEntry?.markNeedsBuild();
          return;
        }
        if (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.tab) {
          _startHashtagSelection();
          _onHashtagSelected(suggestions[_dropdownSelectedIndex]);
          return;
        }
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          _hideHashtagDropdown();
          return;
        }
      }
    }

    final isModifierPressed = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;

    if (isModifierPressed) {
      if (event.logicalKey == LogicalKeyboardKey.keyB) {
        _toggleBold();
        return;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyI) {
        _toggleItalic();
        return;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyV) {
        // Check for image paste
        _handleImagePaste();
        // Don't return - let the default paste happen for text
      }
    }

    if (event.logicalKey == LogicalKeyboardKey.enter) {
      _handleEnterKey();
    }
  }

  /// Handle pasting images from clipboard
  Future<void> _handleImagePaste() async {
    if (widget.onImagePaste == null || _isUploadingImage) return;

    try {
      // Check for image in clipboard using pasteboard
      final imageBytes = await Pasteboard.image;
      if (imageBytes == null || imageBytes.isEmpty) return;

      // Default to PNG since pasteboard returns PNG format
      const mimeType = 'image/png';

      // We have an image - upload it
      setState(() => _isUploadingImage = true);

      // Insert a placeholder at cursor position
      final selection = _controller!.selection;
      final cursorPos = selection.isValid ? selection.start : _controller!.text.length;
      const placeholder = '[img...]';
      _uploadingPlaceholder = placeholder;

      final text = _controller!.text;
      final newText = '${text.substring(0, cursorPos)}$placeholder${text.substring(cursorPos)}';

      _controller!.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: cursorPos + placeholder.length),
      );
      widget.onChanged?.call(newText);

      // Upload the image - returns the 1-based index of the new image
      final imageIndex = await widget.onImagePaste!(imageBytes, mimeType);

      if (imageIndex != null && mounted) {
        // Replace placeholder with actual image reference [img1], [img2], etc.
        final currentText = _controller!.text;
        final imageRef = '[img$imageIndex]';
        final updatedText = currentText.replaceFirst(placeholder, imageRef);

        _controller!.value = TextEditingValue(
          text: updatedText,
          selection: TextSelection.collapsed(
            offset: _controller!.selection.start + (imageRef.length - placeholder.length),
          ),
        );
        widget.onChanged?.call(updatedText);
      } else if (mounted) {
        // Upload failed - remove placeholder
        final currentText = _controller!.text;
        final updatedText = currentText.replaceFirst(placeholder, '');
        _controller!.text = updatedText;
        widget.onChanged?.call(updatedText);
      }
    } catch (e) {
      // Silently fail - might just be text paste
      if (_uploadingPlaceholder != null && mounted) {
        final currentText = _controller!.text;
        final updatedText = currentText.replaceFirst(_uploadingPlaceholder!, '');
        _controller!.text = updatedText;
        widget.onChanged?.call(updatedText);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingImage = false;
          _uploadingPlaceholder = null;
        });
      }
    }
  }

  void _toggleBold() {
    _isToolbarInteraction = true;
    _wrapSelection('**', '**');
    _lastSelection = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
        Future.delayed(const Duration(milliseconds: 50), () {
          _isToolbarInteraction = false;
        });
      }
    });
  }

  void _toggleItalic() {
    _isToolbarInteraction = true;
    _wrapSelection('*', '*');
    _lastSelection = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
        Future.delayed(const Duration(milliseconds: 50), () {
          _isToolbarInteraction = false;
        });
      }
    });
  }

  void _wrapSelection(String before, String after) {
    final text = _controller!.text;
    var selection = _controller!.selection;

    if (!selection.isValid || selection.isCollapsed) {
      if (_lastSelection != null && _lastSelection!.isValid && !_lastSelection!.isCollapsed) {
        if (_lastSelection!.start <= text.length && _lastSelection!.end <= text.length) {
          selection = _lastSelection!;
        } else {
          return;
        }
      } else {
        return;
      }
    }

    final selectedText = selection.textInside(text);
    final start = selection.start;
    final end = selection.end;
    final beforeLen = before.length;
    final afterLen = after.length;

    // Check if already wrapped - unwrap
    if (start >= beforeLen && end + afterLen <= text.length) {
      final potentialBefore = text.substring(start - beforeLen, start);
      final potentialAfter = text.substring(end, end + afterLen);

      if (potentialBefore == before && potentialAfter == after) {
        final newText = text.substring(0, start - beforeLen) +
            selectedText +
            text.substring(end + afterLen);

        _controller!.value = TextEditingValue(
          text: newText,
          selection: TextSelection(
            baseOffset: start - beforeLen,
            extentOffset: end - beforeLen,
          ),
        );
        widget.onChanged?.call(newText);
        return;
      }
    }

    // Wrap selection
    final newText = text.substring(0, start) +
        before +
        selectedText +
        after +
        text.substring(end);

    final newStart = start + beforeLen;
    final newEnd = newStart + selectedText.length;

    _controller!.value = TextEditingValue(
      text: newText,
      selection: TextSelection(baseOffset: newStart, extentOffset: newEnd),
    );
    widget.onChanged?.call(newText);
  }

  void _handleEnterKey() {
    final text = _controller!.text;
    final selection = _controller!.selection;
    if (!selection.isValid) return;

    final beforeCursor = text.substring(0, selection.start);
    final lines = beforeCursor.split('\n');
    if (lines.isEmpty) return;

    final currentLine = lines.last;
    String? continuation;

    // Bullet list
    final bulletMatch = RegExp(r'^(\s*)([-*])\s').firstMatch(currentLine);
    if (bulletMatch != null) {
      final indent = bulletMatch.group(1) ?? '';
      final bullet = bulletMatch.group(2);
      if (currentLine.trim() == '-' || currentLine.trim() == '*') {
        _removeCurrentLinePrefix(lines, bulletMatch.group(0)!.length);
        return;
      }
      continuation = '$indent$bullet ';
    }

    // Checkbox
    final checkboxMatch = RegExp(r'^(\s*)- \[[x ]\]\s').firstMatch(currentLine);
    if (checkboxMatch != null) {
      final indent = checkboxMatch.group(1) ?? '';
      if (RegExp(r'^(\s*)- \[[x ]\]\s*$').hasMatch(currentLine)) {
        _removeCurrentLinePrefix(lines, checkboxMatch.group(0)!.length);
        return;
      }
      continuation = '$indent- [ ] ';
    }

    // Numbered list
    final numberedMatch = RegExp(r'^(\s*)(\d+)\.\s').firstMatch(currentLine);
    if (numberedMatch != null) {
      final indent = numberedMatch.group(1) ?? '';
      final num = int.tryParse(numberedMatch.group(2) ?? '1') ?? 1;
      if (RegExp(r'^(\s*)\d+\.\s*$').hasMatch(currentLine)) {
        _removeCurrentLinePrefix(lines, numberedMatch.group(0)!.length);
        return;
      }
      continuation = '$indent${num + 1}. ';
    }

    // Quote
    final quoteMatch = RegExp(r'^(\s*)>\s').firstMatch(currentLine);
    if (quoteMatch != null) {
      final indent = quoteMatch.group(1) ?? '';
      if (currentLine.trim() == '>') {
        _removeCurrentLinePrefix(lines, quoteMatch.group(0)!.length);
        return;
      }
      continuation = '$indent> ';
    }

    if (continuation != null) {
      final newText = '${text.substring(0, selection.start)}\n$continuation${text.substring(selection.end)}';
      final newPosition = selection.start + 1 + continuation.length;

      _controller!.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newPosition),
      );
      widget.onChanged?.call(newText);
    }
  }

  void _removeCurrentLinePrefix(List<String> lines, int prefixLength) {
    final text = _controller!.text;
    final selection = _controller!.selection;

    final beforeCursor = text.substring(0, selection.start);
    final lineStart = beforeCursor.lastIndexOf('\n') + 1;

    final newText = text.substring(0, lineStart) + text.substring(selection.start);
    final newPosition = lineStart;

    _controller!.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newPosition),
    );
    widget.onChanged?.call(newText);
  }

  void _toggleCheckbox(String text, int checkboxStart) {
    final isChecked = text.substring(checkboxStart, checkboxStart + 5) == '- [x]';
    final newText = text.substring(0, checkboxStart) +
        (isChecked ? '- [ ]' : '- [x]') +
        text.substring(checkboxStart + 5);

    _controller!.text = newText;
    widget.onChanged?.call(newText);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final controller = _controller;
    if (controller == null) return const SizedBox.shrink();

    final hasContent = controller.text.isNotEmpty;

    // Always use live editor (with styled markdown) when editing
    if (_isEditing || !hasContent || widget.readOnly) {
      return TapRegion(
        onTapOutside: (_) {
          if (_isToolbarInteraction) return;
          _focusNode.unfocus();
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            CompositedTransformTarget(
              link: _layerLink,
              child: KeyboardListener(
                focusNode: FocusNode(),
                onKeyEvent: _handleKeyEvent,
                child: TextField(
                  controller: controller,
                  focusNode: _focusNode,
                  readOnly: widget.readOnly,
                  style: TextStyle(
                    fontSize: 15,
                    color: colors.textSecondary,
                    height: 1.5,
                  ),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    hintText: widget.hintText,
                    hintStyle: TextStyle(color: colors.textPlaceholder),
                    contentPadding: EdgeInsets.zero,
                    isDense: true,
                    filled: false,
                  ),
                  maxLines: null,
                  minLines: 2,
                  onChanged: widget.onChanged,
                ),
              ),
            ),
            if (_isEditing)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    _FormatButton(
                      icon: Icons.format_bold,
                      tooltip: 'Bold (⌘B)',
                      onTapDown: () => _isToolbarInteraction = true,
                      onTap: _toggleBold,
                    ),
                    const SizedBox(width: 4),
                    _FormatButton(
                      icon: Icons.format_italic,
                      tooltip: 'Italic (⌘I)',
                      onTapDown: () => _isToolbarInteraction = true,
                      onTap: _toggleItalic,
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    }

    // Rendered markdown view (when blurred with content)
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (details) {
        final tapPosition = _estimateCursorPosition(context, details.localPosition);
        setState(() => _isEditing = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _focusNode.requestFocus();
          controller.selection = TextSelection.collapsed(
            offset: tapPosition.clamp(0, controller.text.length),
          );
        });
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: _BearMarkdownBody(
          data: controller.text,
          colors: colors,
          imageUrlResolver: widget.imageUrlResolver,
          onImageTap: (attachmentId) {
            // TODO: Open full-size image viewer
          },
          onCheckboxTap: (checkboxStart) {
            _toggleCheckbox(controller.text, checkboxStart);
          },
        ),
      ),
    );
  }

  int _estimateCursorPosition(BuildContext context, Offset localPosition) {
    final text = _controller!.text;
    if (text.isEmpty) return 0;

    const textStyle = TextStyle(fontSize: 15, height: 1.5);
    final textPainter = TextPainter(
      text: TextSpan(text: text, style: textStyle),
      textDirection: TextDirection.ltr,
      maxLines: null,
    );

    final renderBox = context.findRenderObject() as RenderBox?;
    final maxWidth = renderBox?.size.width ?? 300;
    textPainter.layout(maxWidth: maxWidth);

    final position = textPainter.getPositionForOffset(localPosition);
    return position.offset;
  }
}

/// Bear-style hashtag dropdown - simple and clean with keyboard navigation
class _BearHashtagDropdown extends ConsumerWidget {
  final LayerLink link;
  final Offset offset;
  final String query;
  final int selectedIndex;
  final ValueChanged<TaskList> onSelect;
  final VoidCallback onDismiss;
  final VoidCallback onStartSelection;

  const _BearHashtagDropdown({
    required this.link,
    required this.offset,
    required this.query,
    required this.selectedIndex,
    required this.onSelect,
    required this.onDismiss,
    required this.onStartSelection,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suggestions = ref.watch(hashtagSuggestionsProvider);
    final colors = context.flowColors;

    if (suggestions.isEmpty) {
      return const SizedBox.shrink();
    }

    // Clamp selected index to valid range
    final safeSelectedIndex = selectedIndex.clamp(0, suggestions.length - 1);

    return Stack(
      children: [
        // Tap outside to dismiss - but don't block text field input
        Positioned.fill(
          child: GestureDetector(
            onTap: onDismiss,
            behavior: HitTestBehavior.translucent,
          ),
        ),
        // Dropdown positioned right under the hashtag
        CompositedTransformFollower(
          link: link,
          showWhenUnlinked: false,
          offset: Offset(offset.dx, offset.dy + 22), // Position under the hashtag line
          targetAnchor: Alignment.topLeft,
          followerAnchor: Alignment.topLeft,
          child: Material(
            elevation: 0,
            color: Colors.transparent,
            child: Container(
              width: 200,
              constraints: const BoxConstraints(maxHeight: 180),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(20),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: suggestions.length,
                  itemBuilder: (context, index) {
                    final list = suggestions[index];
                    final isSelected = index == safeSelectedIndex;
                    return _BearSuggestionItem(
                      list: list,
                      isSelected: isSelected,
                      onPointerDown: onStartSelection,
                      onTap: () => onSelect(list),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Bear-style suggestion item - minimal and clean
class _BearSuggestionItem extends StatelessWidget {
  final TaskList list;
  final bool isSelected;
  final VoidCallback onPointerDown;
  final VoidCallback onTap;

  const _BearSuggestionItem({
    required this.list,
    required this.isSelected,
    required this.onPointerDown,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final isSublist = list.depth > 0;

    return Listener(
      onPointerDown: (_) => onPointerDown(),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          color: isSelected ? colors.primary.withAlpha(20) : Colors.transparent,
          padding: EdgeInsets.only(
            left: isSublist ? 40 : 12, // More indent for sublists
            right: 12,
            top: isSublist ? 5 : 8,  // Less vertical padding for sublists
            bottom: isSublist ? 5 : 8,
          ),
          child: Row(
            children: [
              // Tag icon only for parent lists
              if (!isSublist) ...[
                Icon(
                  Icons.tag,
                  size: 16,
                  color: colors.primary,
                ),
                const SizedBox(width: 8),
              ],
              // Name display
              Expanded(
                child: Text(
                  isSublist ? '/${list.name}' : list.name,
                  style: TextStyle(
                    fontSize: isSublist ? 12 : 14, // Smaller text for sublists
                    fontWeight: FontWeight.w500,
                    color: isSublist ? colors.textSecondary : colors.textPrimary,
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

/// Rendered markdown body for when field is blurred
class _BearMarkdownBody extends StatelessWidget {
  final String data;
  final FlowColorScheme colors;
  final void Function(int checkboxStart)? onCheckboxTap;
  final ImageUrlResolver? imageUrlResolver;
  final void Function(String attachmentId)? onImageTap;

  const _BearMarkdownBody({
    required this.data,
    required this.colors,
    this.onCheckboxTap,
    this.imageUrlResolver,
    this.onImageTap,
  });

  static final _hashtagRegex = RegExp(r'#([A-Za-z0-9_]+(?:/[A-Za-z0-9_]+)?)');
  static final _imageRegex = RegExp(r'\[img(\d+|\.\.\.)\]');

  @override
  Widget build(BuildContext context) {
    // Check for special patterns that need custom rendering
    final hasHashtags = _hashtagRegex.hasMatch(data);
    final hasImages = _imageRegex.hasMatch(data);

    if (hasHashtags || hasImages) {
      return _buildRichContent(context);
    }

    return MarkdownBody(
      data: data,
      selectable: false,
      styleSheet: _buildStyleSheet(context),
      onTapLink: (text, href, title) {
        if (href != null) launchUrl(Uri.parse(href));
      },
    );
  }

  /// Build rich content with hashtags, images, and markdown
  /// Images are displayed as block elements (own line)
  Widget _buildRichContent(BuildContext context) {
    final widgets = <Widget>[];
    final text = data;

    // Combine all special patterns and sort by position
    final allMatches = <_SpecialMatch>[];

    for (final match in _hashtagRegex.allMatches(text)) {
      allMatches.add(_SpecialMatch(
        type: _MatchType.hashtag,
        start: match.start,
        end: match.end,
        content: match.group(0)!,
        id: match.group(1)!,
      ));
    }

    for (final match in _imageRegex.allMatches(text)) {
      allMatches.add(_SpecialMatch(
        type: _MatchType.image,
        start: match.start,
        end: match.end,
        content: match.group(0)!,
        id: match.group(1)!, // The number or "..."
      ));
    }

    allMatches.sort((a, b) => a.start.compareTo(b.start));

    // Track current inline content for proper block layout
    var lastEnd = 0;
    List<Widget> currentInlineWidgets = [];

    void flushInlineWidgets() {
      if (currentInlineWidgets.isNotEmpty) {
        widgets.add(Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: currentInlineWidgets,
        ));
        currentInlineWidgets = [];
      }
    }

    for (final match in allMatches) {
      // Add text before this match
      if (match.start > lastEnd) {
        final beforeText = text.substring(lastEnd, match.start);
        if (beforeText.trim().isNotEmpty) {
          currentInlineWidgets.add(_buildTextSegmentWidget(beforeText));
        }
      }

      // Add the special element
      if (match.type == _MatchType.hashtag) {
        currentInlineWidgets.add(_buildHashtagWidget(match.content));
      } else if (match.type == _MatchType.image) {
        // Images are block-level - flush any inline content first
        flushInlineWidgets();
        widgets.add(_buildBlockImage(context, match.id));
      }

      lastEnd = match.end;
    }

    // Add remaining text
    if (lastEnd < text.length) {
      final afterText = text.substring(lastEnd);
      if (afterText.trim().isNotEmpty) {
        currentInlineWidgets.add(_buildTextSegmentWidget(afterText));
      }
    }

    // Flush any remaining inline content
    flushInlineWidgets();

    // Use Column for block layout (images on their own lines)
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: widgets,
    );
  }

  Widget _buildTextSegmentWidget(String text) {
    return Text.rich(
      TextSpan(children: _parseTextSegment(text)),
      style: TextStyle(
        fontSize: 15,
        color: colors.textSecondary,
        height: 1.5,
      ),
    );
  }

  Widget _buildHashtagWidget(String hashtag) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colors.surfaceVariant,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        hashtag,
        style: TextStyle(
          fontSize: 14,
          color: colors.textSecondary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  /// Build a block-level image (displayed on its own line)
  /// indexStr is "1", "2", etc. or "..." for uploading
  Widget _buildBlockImage(BuildContext context, String indexStr) {
    // Handle uploading placeholder
    if (indexStr == '...') {
      return Container(
        width: 120,
        height: 90,
        margin: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: colors.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(colors.textTertiary),
            ),
          ),
        ),
      );
    }

    // Parse the index (1-based)
    final imageIndex = int.tryParse(indexStr);
    if (imageIndex == null) {
      return _buildBrokenImagePlaceholder();
    }

    // Get the image URL from resolver using index
    final imageUrl = imageUrlResolver?.call(imageIndex);

    if (imageUrl == null) {
      return _buildBrokenImagePlaceholder();
    }

    // Render actual image with block layout and 400px max
    return GestureDetector(
      onTap: () => onImageTap?.call(imageIndex.toString()),
      child: Container(
        constraints: const BoxConstraints(
          maxWidth: 400,
          maxHeight: 400,
        ),
        margin: const EdgeInsets.symmetric(vertical: 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            imageUrl,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Container(
                width: 120,
                height: 90,
                decoration: BoxDecoration(
                  color: colors.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: loadingProgress.expectedTotalBytes != null
                        ? loadingProgress.cumulativeBytesLoaded /
                            loadingProgress.expectedTotalBytes!
                        : null,
                    valueColor: AlwaysStoppedAnimation(colors.textTertiary),
                  ),
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              return _buildBrokenImagePlaceholder();
            },
          ),
        ),
      ),
    );
  }

  Widget _buildBrokenImagePlaceholder() {
    return Container(
      width: 72,
      height: 48,
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surfaceVariant.withOpacity(0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: colors.border.withOpacity(0.5),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.image_not_supported_outlined,
            color: colors.textTertiary,
            size: 16,
          ),
          const SizedBox(height: 2),
          Text(
            'Removed',
            style: TextStyle(
              fontSize: 9,
              color: colors.textTertiary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  List<InlineSpan> _parseTextSegment(String text) {
    final spans = <InlineSpan>[];
    final boldItalicRegex = RegExp(r'\*\*\*(.+?)\*\*\*|\*\*(.+?)\*\*|\*(.+?)\*|_(.+?)_');
    var lastEnd = 0;

    for (final match in boldItalicRegex.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }

      if (match.group(1) != null) {
        spans.add(TextSpan(
          text: match.group(1),
          style: const TextStyle(fontWeight: FontWeight.bold, fontStyle: FontStyle.italic),
        ));
      } else if (match.group(2) != null) {
        spans.add(TextSpan(
          text: match.group(2),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ));
      } else if (match.group(3) != null) {
        spans.add(TextSpan(
          text: match.group(3),
          style: const TextStyle(fontStyle: FontStyle.italic),
        ));
      } else if (match.group(4) != null) {
        spans.add(TextSpan(
          text: match.group(4),
          style: const TextStyle(fontStyle: FontStyle.italic),
        ));
      }

      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }

    if (spans.isEmpty) {
      spans.add(TextSpan(text: text));
    }

    return spans;
  }

  MarkdownStyleSheet _buildStyleSheet(BuildContext context) {
    return MarkdownStyleSheet(
      p: TextStyle(fontSize: 15, color: colors.textSecondary, height: 1.5),
      h1: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: colors.textPrimary),
      h2: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: colors.textPrimary),
      h3: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: colors.textPrimary),
      code: TextStyle(fontSize: 13, fontFamily: 'monospace', color: colors.textPrimary, backgroundColor: colors.surfaceVariant),
      codeblockDecoration: BoxDecoration(color: colors.surfaceVariant, borderRadius: BorderRadius.circular(8)),
      blockquote: TextStyle(fontSize: 15, color: colors.textSecondary, fontStyle: FontStyle.italic),
      blockquoteDecoration: BoxDecoration(border: Border(left: BorderSide(color: colors.textTertiary, width: 3))),
      listBullet: TextStyle(fontSize: 15, color: colors.textSecondary),
      a: TextStyle(color: colors.primary, decoration: TextDecoration.underline),
      strong: const TextStyle(fontWeight: FontWeight.bold),
      em: const TextStyle(fontStyle: FontStyle.italic),
    );
  }
}

/// Compact format button for inline toolbar
class _FormatButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final VoidCallback? onTapDown;

  const _FormatButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.onTapDown,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;

    return Listener(
      onPointerDown: (_) => onTapDown?.call(),
      onPointerUp: (_) => onTap(),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Tooltip(
          message: tooltip,
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: colors.surfaceVariant.withAlpha(100),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(icon, size: 16, color: colors.textSecondary),
          ),
        ),
      ),
    );
  }
}

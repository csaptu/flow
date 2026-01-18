import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flow_tasks/core/theme/flow_theme.dart';
import 'package:url_launcher/url_launcher.dart';

/// Bear-style markdown description field
///
/// Supported markdown:
/// - Lists: `- ` or `* ` for bullets, `1. ` for numbered
/// - Checkboxes: `- [ ]` unchecked, `- [x]` checked
/// - Code: ``` for blocks, ` for inline
/// - Bold: `**text**`
/// - Italic: `*text*` or `_text_`
/// - Strikethrough: `~~text~~`
/// - Headers: `# `, `## `, `### `
/// - Links: `[text](url)`
/// - Quotes: `> text`
/// - Horizontal rule: `---`
class MarkdownDescriptionField extends StatefulWidget {
  final String? initialValue;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onEditingComplete;
  final bool readOnly;

  const MarkdownDescriptionField({
    super.key,
    this.initialValue,
    this.hintText = 'Add description...',
    this.onChanged,
    this.onEditingComplete,
    this.readOnly = false,
  });

  @override
  State<MarkdownDescriptionField> createState() => _MarkdownDescriptionFieldState();
}

class _MarkdownDescriptionFieldState extends State<MarkdownDescriptionField> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue ?? '');
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(covariant MarkdownDescriptionField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue && !_isEditing) {
      _controller.text = widget.initialValue ?? '';
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    setState(() {
      _isEditing = _focusNode.hasFocus;
    });
    if (!_focusNode.hasFocus) {
      widget.onEditingComplete?.call();
    }
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    // Check for modifier keys (Ctrl on Windows/Linux, Cmd on Mac)
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
    }

    if (event.logicalKey == LogicalKeyboardKey.enter) {
      _handleEnterKey();
    }
  }

  void _toggleBold() {
    _wrapSelection('**', '**');
  }

  void _toggleItalic() {
    _wrapSelection('*', '*');
  }

  void _wrapSelection(String before, String after) {
    final text = _controller.text;
    final selection = _controller.selection;

    if (!selection.isValid) return;

    final selectedText = selection.textInside(text);

    // Check if already wrapped - unwrap if so
    final start = selection.start;
    final end = selection.end;

    final beforeLen = before.length;
    final afterLen = after.length;

    // Check if selection is already wrapped
    if (start >= beforeLen && end + afterLen <= text.length) {
      final potentialBefore = text.substring(start - beforeLen, start);
      final potentialAfter = text.substring(end, end + afterLen);

      if (potentialBefore == before && potentialAfter == after) {
        // Unwrap: remove the markers
        final newText = text.substring(0, start - beforeLen) +
            selectedText +
            text.substring(end + afterLen);

        _controller.value = TextEditingValue(
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

    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection(baseOffset: newStart, extentOffset: newEnd),
    );
    widget.onChanged?.call(newText);
  }

  void _handleEnterKey() {
    final text = _controller.text;
    final selection = _controller.selection;
    if (!selection.isValid) return;

    final beforeCursor = text.substring(0, selection.start);
    final lines = beforeCursor.split('\n');
    if (lines.isEmpty) return;

    final currentLine = lines.last;

    // Check for list patterns to continue
    String? continuation;

    // Bullet list: - or *
    final bulletMatch = RegExp(r'^(\s*)([-*])\s').firstMatch(currentLine);
    if (bulletMatch != null) {
      final indent = bulletMatch.group(1) ?? '';
      final bullet = bulletMatch.group(2);
      // Check if line is empty (just the bullet)
      if (currentLine.trim() == '-' || currentLine.trim() == '*') {
        // Remove the empty bullet and don't continue
        _removeCurrentLinePrefix(lines, bulletMatch.group(0)!.length);
        return;
      }
      continuation = '$indent$bullet ';
    }

    // Checkbox: - [ ] or - [x]
    final checkboxMatch = RegExp(r'^(\s*)- \[[x ]\]\s').firstMatch(currentLine);
    if (checkboxMatch != null) {
      final indent = checkboxMatch.group(1) ?? '';
      // Check if line is empty (just the checkbox)
      if (RegExp(r'^(\s*)- \[[x ]\]\s*$').hasMatch(currentLine)) {
        _removeCurrentLinePrefix(lines, checkboxMatch.group(0)!.length);
        return;
      }
      continuation = '$indent- [ ] ';
    }

    // Numbered list: 1. 2. etc
    final numberedMatch = RegExp(r'^(\s*)(\d+)\.\s').firstMatch(currentLine);
    if (numberedMatch != null) {
      final indent = numberedMatch.group(1) ?? '';
      final num = int.tryParse(numberedMatch.group(2) ?? '1') ?? 1;
      // Check if line is empty (just the number)
      if (RegExp(r'^(\s*)\d+\.\s*$').hasMatch(currentLine)) {
        _removeCurrentLinePrefix(lines, numberedMatch.group(0)!.length);
        return;
      }
      continuation = '$indent${num + 1}. ';
    }

    // Quote: >
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
      // Insert newline with continuation
      final newText = '${text.substring(0, selection.start)}\n$continuation${text.substring(selection.end)}';
      final newPosition = selection.start + 1 + continuation.length;

      _controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newPosition),
      );
      widget.onChanged?.call(newText);
    }
  }

  void _removeCurrentLinePrefix(List<String> lines, int prefixLength) {
    final text = _controller.text;
    final selection = _controller.selection;

    // Find start of current line
    final beforeCursor = text.substring(0, selection.start);
    final lineStart = beforeCursor.lastIndexOf('\n') + 1;

    // Remove the prefix
    final newText = text.substring(0, lineStart) + text.substring(selection.start);
    final newPosition = lineStart;

    _controller.value = TextEditingValue(
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

    _controller.text = newText;
    widget.onChanged?.call(newText);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final hasContent = _controller.text.isNotEmpty;

    // Show editor when editing or empty, show rendered markdown otherwise
    if (_isEditing || !hasContent || widget.readOnly) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          KeyboardListener(
            focusNode: FocusNode(),
            onKeyEvent: _handleKeyEvent,
            child: TextField(
              controller: _controller,
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
              onTapOutside: (_) {
                _focusNode.unfocus();
              },
            ),
          ),
          // Formatting toolbar - only show when editing and has focus
          if (_isEditing)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  _FormatButton(
                    icon: Icons.format_bold,
                    tooltip: 'Bold (⌘B)',
                    onTap: _toggleBold,
                  ),
                  const SizedBox(width: 4),
                  _FormatButton(
                    icon: Icons.format_italic,
                    tooltip: 'Italic (⌘I)',
                    onTap: _toggleItalic,
                  ),
                ],
              ),
            ),
        ],
      );
    }

    // Rendered markdown view
    return GestureDetector(
      onTap: () {
        // First switch to edit mode, then request focus after build
        setState(() => _isEditing = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _focusNode.requestFocus();
        });
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: _BearMarkdownBody(
          data: _controller.text,
          colors: colors,
          onCheckboxTap: (checkboxStart) {
            _toggleCheckbox(_controller.text, checkboxStart);
          },
        ),
      ),
    );
  }
}

/// Custom markdown body with Bear-style rendering
class _BearMarkdownBody extends StatelessWidget {
  final String data;
  final FlowColorScheme colors;
  final void Function(int checkboxStart)? onCheckboxTap;

  const _BearMarkdownBody({
    required this.data,
    required this.colors,
    this.onCheckboxTap,
  });

  @override
  Widget build(BuildContext context) {
    return MarkdownBody(
      data: _preprocessCheckboxes(data),
      selectable: true,
      styleSheet: _buildStyleSheet(context),
      onTapLink: (text, href, title) {
        if (href != null) {
          launchUrl(Uri.parse(href));
        }
      },
      checkboxBuilder: (checked) {
        return SizedBox(
          width: 20,
          height: 20,
          child: Checkbox(
            value: checked,
            onChanged: (_) {
              // Find and toggle this checkbox
              // This is handled by onCheckboxTap in parent
            },
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
            side: BorderSide(color: colors.textTertiary),
            activeColor: colors.primary,
          ),
        );
      },
    );
  }

  // Convert - [ ] and - [x] to proper task list format
  String _preprocessCheckboxes(String text) {
    return text
        .replaceAllMapped(
          RegExp(r'^(\s*)- \[ \](.*)$', multiLine: true),
          (m) => '${m.group(1)}- [ ]${m.group(2)}',
        )
        .replaceAllMapped(
          RegExp(r'^(\s*)- \[x\](.*)$', multiLine: true),
          (m) => '${m.group(1)}- [x]${m.group(2)}',
        );
  }

  MarkdownStyleSheet _buildStyleSheet(BuildContext context) {
    return MarkdownStyleSheet(
      // Paragraph
      p: TextStyle(
        fontSize: 15,
        color: colors.textSecondary,
        height: 1.5,
      ),

      // Headers
      h1: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.bold,
        color: colors.textPrimary,
        height: 1.4,
      ),
      h2: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: colors.textPrimary,
        height: 1.4,
      ),
      h3: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: colors.textPrimary,
        height: 1.4,
      ),

      // Code
      code: TextStyle(
        fontSize: 13,
        fontFamily: 'monospace',
        color: colors.textPrimary,
        backgroundColor: colors.surfaceVariant,
      ),
      codeblockDecoration: BoxDecoration(
        color: colors.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
      ),
      codeblockPadding: const EdgeInsets.all(12),

      // Blockquote
      blockquote: TextStyle(
        fontSize: 15,
        color: colors.textSecondary,
        fontStyle: FontStyle.italic,
        height: 1.5,
      ),
      blockquoteDecoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: colors.textTertiary,
            width: 3,
          ),
        ),
      ),
      blockquotePadding: const EdgeInsets.only(left: 12),

      // Lists
      listBullet: TextStyle(
        fontSize: 15,
        color: colors.textSecondary,
      ),
      listIndent: 24,

      // Links
      a: TextStyle(
        color: colors.primary,
        decoration: TextDecoration.underline,
        decorationColor: colors.primary.withAlpha(100),
      ),

      // Strong/Em
      strong: const TextStyle(fontWeight: FontWeight.bold),
      em: const TextStyle(fontStyle: FontStyle.italic),
      del: TextStyle(
        decoration: TextDecoration.lineThrough,
        color: colors.textTertiary,
      ),

      // Horizontal rule
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: colors.divider,
            width: 1,
          ),
        ),
      ),

      // Table (if needed)
      tableHead: TextStyle(
        fontWeight: FontWeight.w600,
        color: colors.textPrimary,
      ),
      tableBody: TextStyle(
        color: colors.textSecondary,
      ),
      tableBorder: TableBorder.all(
        color: colors.divider,
        width: 1,
      ),
      tableColumnWidth: const IntrinsicColumnWidth(),
      tableCellsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    );
  }
}

/// Markdown formatting toolbar (optional, can be added later)
class MarkdownToolbar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback? onChanged;

  const MarkdownToolbar({
    super.key,
    required this.controller,
    this.onChanged,
  });

  void _insertMarkdown(String before, String after, {String? placeholder}) {
    final text = controller.text;
    final selection = controller.selection;

    if (!selection.isValid) return;

    final selectedText = selection.textInside(text);
    final insertText = selectedText.isEmpty ? (placeholder ?? '') : selectedText;

    final newText = text.substring(0, selection.start) +
        before +
        insertText +
        after +
        text.substring(selection.end);

    final newPosition = selection.start + before.length + insertText.length;

    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newPosition),
    );
    onChanged?.call();
  }

  void _toggleLinePrefix(String prefix) {
    final text = controller.text;
    final selection = controller.selection;

    if (!selection.isValid) return;

    // Find current line
    final beforeCursor = text.substring(0, selection.start);
    final lineStart = beforeCursor.lastIndexOf('\n') + 1;
    final lineEnd = text.indexOf('\n', selection.start);
    final actualLineEnd = lineEnd == -1 ? text.length : lineEnd;

    final currentLine = text.substring(lineStart, actualLineEnd);

    String newText;
    int newPosition;

    if (currentLine.startsWith(prefix)) {
      // Remove prefix
      newText = text.substring(0, lineStart) +
          currentLine.substring(prefix.length) +
          text.substring(actualLineEnd);
      newPosition = selection.start - prefix.length;
    } else {
      // Add prefix
      newText = text.substring(0, lineStart) +
          prefix +
          currentLine +
          text.substring(actualLineEnd);
      newPosition = selection.start + prefix.length;
    }

    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newPosition.clamp(0, newText.length)),
    );
    onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;

    return Container(
      height: 44,
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: colors.divider, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          _ToolbarButton(
            icon: Icons.format_bold,
            tooltip: 'Bold',
            onTap: () => _insertMarkdown('**', '**', placeholder: 'bold'),
          ),
          _ToolbarButton(
            icon: Icons.format_italic,
            tooltip: 'Italic',
            onTap: () => _insertMarkdown('*', '*', placeholder: 'italic'),
          ),
          _ToolbarButton(
            icon: Icons.format_strikethrough,
            tooltip: 'Strikethrough',
            onTap: () => _insertMarkdown('~~', '~~', placeholder: 'strikethrough'),
          ),
          _ToolbarButton(
            icon: Icons.code,
            tooltip: 'Inline code',
            onTap: () => _insertMarkdown('`', '`', placeholder: 'code'),
          ),
          _ToolbarButton(
            icon: Icons.format_list_bulleted,
            tooltip: 'Bullet list',
            onTap: () => _toggleLinePrefix('- '),
          ),
          _ToolbarButton(
            icon: Icons.check_box_outlined,
            tooltip: 'Checkbox',
            onTap: () => _toggleLinePrefix('- [ ] '),
          ),
          _ToolbarButton(
            icon: Icons.format_quote,
            tooltip: 'Quote',
            onTap: () => _toggleLinePrefix('> '),
          ),
          _ToolbarButton(
            icon: Icons.link,
            tooltip: 'Link',
            onTap: () => _insertMarkdown('[', '](url)', placeholder: 'link text'),
          ),
        ],
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _ToolbarButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;

    return IconButton(
      icon: Icon(icon, size: 20),
      color: colors.textSecondary,
      tooltip: tooltip,
      onPressed: onTap,
      splashRadius: 20,
    );
  }
}

/// Compact format button for inline toolbar
class _FormatButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _FormatButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
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
    );
  }
}

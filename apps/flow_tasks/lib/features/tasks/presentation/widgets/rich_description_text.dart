import 'package:flutter/material.dart';
import 'package:flow_tasks/core/theme/flow_theme.dart';

/// A lightweight widget that parses and renders markdown-style text:
/// - Bold: **text** or __text__
/// - Italic: *text* or _text_
/// - Hashtags: #tag as styled pills
class RichDescriptionText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  const RichDescriptionText({
    super.key,
    required this.text,
    this.style,
    this.maxLines,
    this.overflow,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final baseStyle = style ?? TextStyle(fontSize: 13, color: colors.textSecondary);

    final spans = _parseText(text, baseStyle, colors);

    return Text.rich(
      TextSpan(children: spans),
      maxLines: maxLines,
      overflow: overflow,
    );
  }

  List<InlineSpan> _parseText(String text, TextStyle baseStyle, FlowColorScheme colors) {
    final spans = <InlineSpan>[];
    final regex = RegExp(
      r'(\*\*(.+?)\*\*)|'     // Bold with **
      r'(__(.+?)__)|'          // Bold with __
      r'(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)|'  // Italic with single *
      r'(?<!_)_(?!_)(.+?)(?<!_)_(?!_)|'        // Italic with single _
      r'(#[\w/]+)',            // Hashtag
    );

    int lastEnd = 0;

    for (final match in regex.allMatches(text)) {
      // Add plain text before this match
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: text.substring(lastEnd, match.start),
          style: baseStyle,
        ));
      }

      final fullMatch = match.group(0)!;

      if (fullMatch.startsWith('**') && fullMatch.endsWith('**')) {
        // Bold with **
        final content = match.group(2);
        spans.add(TextSpan(
          text: content,
          style: baseStyle.copyWith(fontWeight: FontWeight.bold),
        ));
      } else if (fullMatch.startsWith('__') && fullMatch.endsWith('__')) {
        // Bold with __
        final content = match.group(4);
        spans.add(TextSpan(
          text: content,
          style: baseStyle.copyWith(fontWeight: FontWeight.bold),
        ));
      } else if (fullMatch.startsWith('*') && fullMatch.endsWith('*') && !fullMatch.startsWith('**')) {
        // Italic with *
        final content = match.group(5);
        spans.add(TextSpan(
          text: content,
          style: baseStyle.copyWith(fontStyle: FontStyle.italic),
        ));
      } else if (fullMatch.startsWith('_') && fullMatch.endsWith('_') && !fullMatch.startsWith('__')) {
        // Italic with _
        final content = match.group(6);
        spans.add(TextSpan(
          text: content,
          style: baseStyle.copyWith(fontStyle: FontStyle.italic),
        ));
      } else if (fullMatch.startsWith('#')) {
        // Hashtag - render as styled pill
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              fullMatch,
              style: baseStyle.copyWith(
                color: colors.primary,
                fontSize: (baseStyle.fontSize ?? 13) - 1,
              ),
            ),
          ),
        ));
      }

      lastEnd = match.end;
    }

    // Add remaining plain text
    if (lastEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastEnd),
        style: baseStyle,
      ));
    }

    // Return at least an empty span if nothing was parsed
    if (spans.isEmpty) {
      spans.add(TextSpan(text: text, style: baseStyle));
    }

    return spans;
  }
}

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flow_tasks/core/theme/flow_theme.dart';

/// A text widget that highlights hashtags (#List or #List/Sublist)
class HashtagText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TextStyle? hashtagStyle;
  final int? maxLines;
  final TextOverflow? overflow;
  final ValueChanged<String>? onHashtagTap;

  const HashtagText({
    super.key,
    required this.text,
    this.style,
    this.hashtagStyle,
    this.maxLines,
    this.overflow,
    this.onHashtagTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final defaultStyle = style ?? TextStyle(color: colors.textPrimary);
    final defaultHashtagStyle = hashtagStyle ?? TextStyle(color: colors.primary);

    final spans = _parseHashtags(text, defaultStyle, defaultHashtagStyle);

    return Text.rich(
      TextSpan(children: spans),
      maxLines: maxLines,
      overflow: overflow,
    );
  }

  List<InlineSpan> _parseHashtags(
    String text,
    TextStyle normalStyle,
    TextStyle hashtagStyle,
  ) {
    final spans = <InlineSpan>[];
    // Match hashtags: #word or #word/subword (alphanumeric + underscore, with optional slash for sublists)
    final regex = RegExp(r'#[\w]+(?:/[\w]+)?');

    int lastMatchEnd = 0;

    for (final match in regex.allMatches(text)) {
      // Add text before the hashtag
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(
          text: text.substring(lastMatchEnd, match.start),
          style: normalStyle,
        ));
      }

      // Add the hashtag
      final hashtag = match.group(0)!;
      spans.add(TextSpan(
        text: hashtag,
        style: hashtagStyle,
        recognizer: onHashtagTap != null
            ? (TapGestureRecognizer()..onTap = () => onHashtagTap!(hashtag.substring(1)))
            : null,
      ));

      lastMatchEnd = match.end;
    }

    // Add remaining text
    if (lastMatchEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastMatchEnd),
        style: normalStyle,
      ));
    }

    return spans;
  }
}

/// A selectable text widget that highlights hashtags
class SelectableHashtagText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TextStyle? hashtagStyle;
  final int? maxLines;
  final ValueChanged<String>? onHashtagTap;

  const SelectableHashtagText({
    super.key,
    required this.text,
    this.style,
    this.hashtagStyle,
    this.maxLines,
    this.onHashtagTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final defaultStyle = style ?? TextStyle(color: colors.textPrimary);
    final defaultHashtagStyle = hashtagStyle ?? TextStyle(color: colors.primary);

    final spans = _parseHashtags(text, defaultStyle, defaultHashtagStyle);

    return SelectableText.rich(
      TextSpan(children: spans),
      maxLines: maxLines,
    );
  }

  List<InlineSpan> _parseHashtags(
    String text,
    TextStyle normalStyle,
    TextStyle hashtagStyle,
  ) {
    final spans = <InlineSpan>[];
    final regex = RegExp(r'#[\w]+(?:/[\w]+)?');

    int lastMatchEnd = 0;

    for (final match in regex.allMatches(text)) {
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(
          text: text.substring(lastMatchEnd, match.start),
          style: normalStyle,
        ));
      }

      final hashtag = match.group(0)!;
      spans.add(TextSpan(
        text: hashtag,
        style: hashtagStyle,
        recognizer: onHashtagTap != null
            ? (TapGestureRecognizer()..onTap = () => onHashtagTap!(hashtag.substring(1)))
            : null,
      ));

      lastMatchEnd = match.end;
    }

    if (lastMatchEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastMatchEnd),
        style: normalStyle,
      ));
    }

    return spans;
  }
}

/// Extracts hashtags from text
List<String> extractHashtags(String text) {
  final regex = RegExp(r'#([\w]+(?:/[\w]+)?)');
  return regex.allMatches(text).map((m) => m.group(1)!).toList();
}

/// Removes all hashtags from text
String removeHashtags(String text) {
  return text.replaceAll(RegExp(r'#[\w]+(?:/[\w]+)?\s*'), '').trim();
}

/// Adds a hashtag to text if not already present
String addHashtagToText(String text, String listPath) {
  final hashtag = '#$listPath';

  // Check if hashtag already exists
  if (text.contains(hashtag)) {
    return text;
  }

  // Add hashtag at the beginning or end
  if (text.trim().isEmpty) {
    return hashtag;
  }

  return '$hashtag $text';
}

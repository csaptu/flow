import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flow_models/flow_models.dart';
import 'package:flow_tasks/core/theme/flow_theme.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';

// Web-specific imports for download
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html if (dart.library.io) 'package:flow_tasks/core/utils/html_stub.dart';

// Platform-specific imports for file handling
import 'dart:io' if (dart.library.html) 'package:flow_tasks/core/utils/io_stub.dart' as io;

/// Displays a list of task attachments
class AttachmentList extends StatelessWidget {
  final List<Attachment> attachments;
  final ValueChanged<Attachment>? onDelete;
  final bool compact;

  const AttachmentList({
    super.key,
    required this.attachments,
    this.onDelete,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) return const SizedBox.shrink();

    // Group attachments by type
    final links = attachments.where((a) => a.isLink).toList();
    final images = attachments.where((a) => a.isImage).toList();
    final documents = attachments.where((a) => a.isDocument).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (images.isNotEmpty) ...[
          _ImageGrid(images: images, onDelete: onDelete),
          const SizedBox(height: 8),
        ],
        if (links.isNotEmpty) ...[
          ...links.map((link) => _LinkTile(
                attachment: link,
                onDelete: onDelete != null ? () => onDelete!(link) : null,
                compact: compact,
              )),
        ],
        if (documents.isNotEmpty) ...[
          ...documents.map((doc) => _DocumentTile(
                attachment: doc,
                onDelete: onDelete != null ? () => onDelete!(doc) : null,
                compact: compact,
              )),
        ],
      ],
    );
  }
}

/// Grid of image thumbnails - 4 per row
class _ImageGrid extends StatefulWidget {
  final List<Attachment> images;
  final ValueChanged<Attachment>? onDelete;

  const _ImageGrid({
    required this.images,
    this.onDelete,
  });

  @override
  State<_ImageGrid> createState() => _ImageGridState();
}

class _ImageGridState extends State<_ImageGrid> {
  // Track which image is pending delete confirmation
  String? _pendingDeleteId;

  // Thumbnail size: smaller to fit 4 per row with spacing
  static const double _thumbnailSize = 56.0;

  void _onDeleteTap(Attachment image) {
    if (_pendingDeleteId == image.id) {
      // Second tap - confirm delete
      widget.onDelete?.call(image);
      setState(() => _pendingDeleteId = null);
    } else {
      // First tap - show confirmation
      setState(() => _pendingDeleteId = image.id);
      // Auto-reset after 3 seconds
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && _pendingDeleteId == image.id) {
          setState(() => _pendingDeleteId = null);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: widget.images.map((image) {
        final isPendingDelete = _pendingDeleteId == image.id;
        return GestureDetector(
          onTap: isPendingDelete ? null : () => _viewImage(context, image),
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: _buildImageWidget(image, colors),
              ),
              // Delete confirmation overlay - covers entire thumbnail
              if (widget.onDelete != null)
                if (isPendingDelete)
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: () => _onDeleteTap(image),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.red.withAlpha(180),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.close_rounded,
                            size: 28,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  Positioned(
                    top: 2,
                    right: 2,
                    child: GestureDetector(
                      onTap: () => _onDeleteTap(image),
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(150),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close,
                          size: 10,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildImageWidget(Attachment image, FlowColorScheme colors) {
    final url = image.thumbnailUrl ?? image.url;

    // Handle data URLs (base64 encoded images)
    if (url.startsWith('data:')) {
      try {
        // Extract base64 data from data URL
        final parts = url.split(',');
        if (parts.length == 2) {
          final bytes = base64Decode(parts[1]);
          return Image.memory(
            bytes,
            width: _thumbnailSize,
            height: _thumbnailSize,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _buildPlaceholder(colors),
          );
        }
      } catch (_) {
        return _buildPlaceholder(colors);
      }
    }

    // Handle HTTP URLs
    return Image.network(
      url,
      width: _thumbnailSize,
      height: _thumbnailSize,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _buildPlaceholder(colors),
    );
  }

  Widget _buildPlaceholder(FlowColorScheme colors) {
    return Container(
      width: _thumbnailSize,
      height: _thumbnailSize,
      decoration: BoxDecoration(
        color: colors.border.withOpacity(0.3),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(
        Icons.image_rounded,
        size: 20,
        color: colors.textTertiary,
      ),
    );
  }

  void _viewImage(BuildContext context, Attachment image) {
    Widget imageWidget;
    final url = image.url;

    // Handle data URLs (base64 encoded images)
    if (url.startsWith('data:')) {
      try {
        final parts = url.split(',');
        if (parts.length == 2) {
          final bytes = base64Decode(parts[1]);
          imageWidget = Image.memory(bytes, fit: BoxFit.contain);
        } else {
          imageWidget = const Center(child: Text('Failed to load image', style: TextStyle(color: Colors.white)));
        }
      } catch (_) {
        imageWidget = const Center(child: Text('Failed to load image', style: TextStyle(color: Colors.white)));
      }
    } else {
      imageWidget = Image.network(url, fit: BoxFit.contain);
    }

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Stack(
          children: [
            InteractiveViewer(child: imageWidget),
            // Top bar with close and download buttons
            Positioned(
              top: 8,
              right: 8,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Download button
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.download, color: Colors.white),
                      tooltip: 'Download',
                      onPressed: () => _downloadImage(image),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Close button
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
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

  Future<void> _downloadImage(Attachment image) async {
    final url = image.url;

    if (kIsWeb) {
      try {
        final anchor = html.AnchorElement()
          ..href = url
          ..download = image.name;
        html.document.body?.append(anchor);
        anchor.click();
        anchor.remove();
      } catch (e) {
        debugPrint('Failed to download image: $e');
      }
    } else {
      // Native platforms: save to temp and open
      try {
        List<int> bytes;

        if (url.startsWith('data:')) {
          // Data URL: decode base64
          final parts = url.split(',');
          if (parts.length != 2) return;
          bytes = base64Decode(parts[1]);
        } else {
          // HTTP URL: would need to download - skip for now
          debugPrint('HTTP image download not implemented for native');
          return;
        }

        final tempDir = await getTemporaryDirectory();
        final filePath = '${tempDir.path}/${image.name}';
        final file = io.File(filePath);
        await file.writeAsBytes(bytes);
        await OpenFilex.open(filePath);
      } catch (e) {
        debugPrint('Failed to download image: $e');
      }
    }
  }
}

/// Link attachment tile with two-tap delete confirmation
class _LinkTile extends StatefulWidget {
  final Attachment attachment;
  final VoidCallback? onDelete;
  final bool compact;

  const _LinkTile({
    required this.attachment,
    this.onDelete,
    this.compact = false,
  });

  @override
  State<_LinkTile> createState() => _LinkTileState();
}

class _LinkTileState extends State<_LinkTile> {
  bool _pendingDelete = false;

  void _onDeleteTap() {
    if (_pendingDelete) {
      // Second tap - confirm delete
      widget.onDelete?.call();
      setState(() => _pendingDelete = false);
    } else {
      // First tap - show confirmation
      setState(() => _pendingDelete = true);
      // Auto-reset after 3 seconds
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && _pendingDelete) {
          setState(() => _pendingDelete = false);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final metadata = widget.attachment.metadata;
    final title = metadata['title'] as String? ?? widget.attachment.name;
    final favicon = metadata['favicon'] as String?;
    final host = _extractHost(widget.attachment.url);

    return Padding(
      padding: EdgeInsets.only(bottom: widget.compact ? 4 : 8),
      child: InkWell(
        onTap: () => _openUrl(widget.attachment.url),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: widget.compact ? 8 : 12,
            vertical: widget.compact ? 6 : 8,
          ),
          child: Row(
            children: [
              // Favicon or icon
              Container(
                width: widget.compact ? 24 : 32,
                height: widget.compact ? 24 : 32,
                decoration: BoxDecoration(
                  color: Colors.blue.withAlpha(25),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: favicon != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.network(
                          favicon,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Icon(
                            Icons.link_rounded,
                            size: widget.compact ? 14 : 18,
                            color: Colors.blue,
                          ),
                        ),
                      )
                    : Icon(
                        Icons.link_rounded,
                        size: widget.compact ? 14 : 18,
                        color: Colors.blue,
                      ),
              ),
              SizedBox(width: widget.compact ? 8 : 12),
              // Title and URL
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: widget.compact ? 13 : 14,
                        fontWeight: FontWeight.w500,
                        color: colors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (!widget.compact) ...[
                      const SizedBox(height: 2),
                      Text(
                        host,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              // Delete button with two-tap confirmation
              if (widget.onDelete != null)
                GestureDetector(
                  onTap: _onDeleteTap,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: EdgeInsets.symmetric(
                      horizontal: _pendingDelete ? 12 : 6,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _pendingDelete ? Colors.red : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      Icons.close_rounded,
                      size: _pendingDelete ? 18 : (widget.compact ? 16 : 18),
                      color: _pendingDelete ? Colors.white : colors.textTertiary,
                    ),
                  ),
                )
              else
                Icon(
                  Icons.open_in_new_rounded,
                  size: widget.compact ? 14 : 16,
                  color: colors.textTertiary,
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _extractHost(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host;
    } catch (_) {
      return url;
    }
  }

  Future<void> _openUrl(String url) async {
    String normalizedUrl = url;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      normalizedUrl = 'https://$url';
    }

    final uri = Uri.parse(normalizedUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

/// Document attachment tile with two-tap delete confirmation
class _DocumentTile extends StatefulWidget {
  final Attachment attachment;
  final VoidCallback? onDelete;
  final bool compact;

  const _DocumentTile({
    required this.attachment,
    this.onDelete,
    this.compact = false,
  });

  @override
  State<_DocumentTile> createState() => _DocumentTileState();
}

class _DocumentTileState extends State<_DocumentTile> {
  bool _pendingDelete = false;

  void _onDeleteTap() {
    if (_pendingDelete) {
      // Second tap - confirm delete
      widget.onDelete?.call();
      setState(() => _pendingDelete = false);
    } else {
      // First tap - show confirmation
      setState(() => _pendingDelete = true);
      // Auto-reset after 3 seconds
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && _pendingDelete) {
          setState(() => _pendingDelete = false);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final iconData = _getIconForMimeType(widget.attachment.mimeType);
    final iconColor = _getColorForMimeType(widget.attachment.mimeType);

    return Padding(
      padding: EdgeInsets.only(bottom: widget.compact ? 4 : 8),
      child: InkWell(
        onTap: () => _openDocument(widget.attachment.url),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: widget.compact ? 8 : 12,
            vertical: widget.compact ? 6 : 8,
          ),
          child: Row(
            children: [
              // File icon
              Container(
                width: widget.compact ? 24 : 32,
                height: widget.compact ? 24 : 32,
                decoration: BoxDecoration(
                  color: iconColor.withAlpha(25),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  iconData,
                  size: widget.compact ? 14 : 18,
                  color: iconColor,
                ),
              ),
              SizedBox(width: widget.compact ? 8 : 12),
              // Filename and size
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.attachment.name,
                      style: TextStyle(
                        fontSize: widget.compact ? 13 : 14,
                        fontWeight: FontWeight.w500,
                        color: colors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (!widget.compact && widget.attachment.formattedSize.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        widget.attachment.formattedSize,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Delete button with two-tap confirmation
              if (widget.onDelete != null)
                GestureDetector(
                  onTap: _onDeleteTap,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: EdgeInsets.symmetric(
                      horizontal: _pendingDelete ? 12 : 6,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _pendingDelete ? Colors.red : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      Icons.close_rounded,
                      size: _pendingDelete ? 18 : (widget.compact ? 16 : 18),
                      color: _pendingDelete ? Colors.white : colors.textTertiary,
                    ),
                  ),
                )
              else
                Icon(
                  Icons.download_rounded,
                  size: widget.compact ? 14 : 16,
                  color: colors.textTertiary,
                ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getIconForMimeType(String? mimeType) {
    if (mimeType == null) return Icons.insert_drive_file_rounded;

    if (mimeType.contains('pdf')) return Icons.picture_as_pdf_rounded;
    if (mimeType.contains('word') || mimeType.contains('document')) {
      return Icons.description_rounded;
    }
    if (mimeType.contains('sheet') || mimeType.contains('excel')) {
      return Icons.table_chart_rounded;
    }
    if (mimeType.contains('presentation') || mimeType.contains('powerpoint')) {
      return Icons.slideshow_rounded;
    }
    if (mimeType.contains('text')) return Icons.article_rounded;

    return Icons.insert_drive_file_rounded;
  }

  Color _getColorForMimeType(String? mimeType) {
    if (mimeType == null) return Colors.grey;

    if (mimeType.contains('pdf')) return Colors.red;
    if (mimeType.contains('word') || mimeType.contains('document')) {
      return Colors.blue;
    }
    if (mimeType.contains('sheet') || mimeType.contains('excel')) {
      return Colors.green;
    }
    if (mimeType.contains('presentation') || mimeType.contains('powerpoint')) {
      return Colors.orange;
    }
    if (mimeType.contains('text')) return Colors.blueGrey;

    return Colors.grey;
  }

  Future<void> _openDocument(String url) async {
    // Handle data URLs (base64 encoded files)
    if (url.startsWith('data:')) {
      if (kIsWeb) {
        _downloadDataUrlWeb(url, widget.attachment.name);
      } else {
        await _openDataUrlNative(url, widget.attachment.name);
      }
      return;
    }

    // Handle regular HTTP URLs
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _downloadDataUrlWeb(String dataUrl, String filename) {
    if (!kIsWeb) return;

    try {
      // Create a download link and trigger it
      final anchor = html.AnchorElement()
        ..href = dataUrl
        ..download = filename;
      html.document.body?.append(anchor);
      anchor.click();
      anchor.remove();
    } catch (e) {
      debugPrint('Failed to download: $e');
    }
  }

  Future<void> _openDataUrlNative(String dataUrl, String filename) async {
    if (kIsWeb) return;

    try {
      // Extract base64 data from data URL
      final parts = dataUrl.split(',');
      if (parts.length != 2) {
        debugPrint('Invalid data URL format');
        return;
      }

      final bytes = base64Decode(parts[1]);

      // Get temp directory and save file
      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/$filename';
      final file = io.File(filePath);
      await file.writeAsBytes(bytes);

      // Open the file with system default app
      await OpenFilex.open(filePath);
    } catch (e) {
      debugPrint('Failed to open document: $e');
    }
  }
}

/// Compact attachment chip for displaying in task tiles
class AttachmentChip extends StatelessWidget {
  final int count;
  final VoidCallback? onTap;

  const AttachmentChip({
    super.key,
    required this.count,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: colors.border.withOpacity(0.3),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.attach_file_rounded,
              size: 14,
              color: colors.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              count.toString(),
              style: TextStyle(
                fontSize: 12,
                color: colors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

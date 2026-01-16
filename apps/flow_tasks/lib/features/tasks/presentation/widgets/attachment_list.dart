import 'package:flutter/material.dart';
import 'package:flow_models/flow_models.dart';
import 'package:flow_tasks/core/theme/flow_theme.dart';
import 'package:url_launcher/url_launcher.dart';

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

/// Grid of image thumbnails
class _ImageGrid extends StatelessWidget {
  final List<Attachment> images;
  final ValueChanged<Attachment>? onDelete;

  const _ImageGrid({
    required this.images,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;

    return SizedBox(
      height: 80,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: images.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final image = images[index];
          return GestureDetector(
            onTap: () => _viewImage(context, image),
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: image.thumbnailUrl != null
                      ? Image.network(
                          image.thumbnailUrl!,
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _buildPlaceholder(colors),
                        )
                      : Image.network(
                          image.url,
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _buildPlaceholder(colors),
                        ),
                ),
                if (onDelete != null)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () => onDelete!(image),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close,
                          size: 12,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildPlaceholder(FlowColorScheme colors) {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: colors.border.withOpacity(0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        Icons.image_rounded,
        color: colors.textTertiary,
      ),
    );
  }

  void _viewImage(BuildContext context, Attachment image) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Stack(
          children: [
            InteractiveViewer(
              child: Image.network(
                image.url,
                fit: BoxFit.contain,
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Link attachment tile
class _LinkTile extends StatelessWidget {
  final Attachment attachment;
  final VoidCallback? onDelete;
  final bool compact;

  const _LinkTile({
    required this.attachment,
    this.onDelete,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final metadata = attachment.metadata;
    final title = metadata['title'] as String? ?? attachment.name;
    final favicon = metadata['favicon'] as String?;
    final host = _extractHost(attachment.url);

    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 4 : 8),
      child: InkWell(
        onTap: () => _openUrl(attachment.url),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 12,
            vertical: compact ? 6 : 8,
          ),
          child: Row(
            children: [
              // Favicon or icon
              Container(
                width: compact ? 24 : 32,
                height: compact ? 24 : 32,
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
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
                            size: compact ? 14 : 18,
                            color: Colors.blue,
                          ),
                        ),
                      )
                    : Icon(
                        Icons.link_rounded,
                        size: compact ? 14 : 18,
                        color: Colors.blue,
                      ),
              ),
              SizedBox(width: compact ? 8 : 12),
              // Title and URL
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: compact ? 13 : 14,
                        fontWeight: FontWeight.w500,
                        color: colors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (!compact) ...[
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
              // Delete button
              if (onDelete != null)
                IconButton(
                  icon: Icon(
                    Icons.close,
                    size: compact ? 16 : 18,
                    color: colors.textTertiary,
                  ),
                  onPressed: onDelete,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(
                    minWidth: compact ? 24 : 32,
                    minHeight: compact ? 24 : 32,
                  ),
                )
              else
                Icon(
                  Icons.open_in_new_rounded,
                  size: compact ? 14 : 16,
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

/// Document attachment tile
class _DocumentTile extends StatelessWidget {
  final Attachment attachment;
  final VoidCallback? onDelete;
  final bool compact;

  const _DocumentTile({
    required this.attachment,
    this.onDelete,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final iconData = _getIconForMimeType(attachment.mimeType);
    final iconColor = _getColorForMimeType(attachment.mimeType);

    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 4 : 8),
      child: InkWell(
        onTap: () => _openDocument(attachment.url),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 12,
            vertical: compact ? 6 : 8,
          ),
          child: Row(
            children: [
              // File icon
              Container(
                width: compact ? 24 : 32,
                height: compact ? 24 : 32,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  iconData,
                  size: compact ? 14 : 18,
                  color: iconColor,
                ),
              ),
              SizedBox(width: compact ? 8 : 12),
              // Filename and size
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      attachment.name,
                      style: TextStyle(
                        fontSize: compact ? 13 : 14,
                        fontWeight: FontWeight.w500,
                        color: colors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (!compact && attachment.formattedSize.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        attachment.formattedSize,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Delete button
              if (onDelete != null)
                IconButton(
                  icon: Icon(
                    Icons.close,
                    size: compact ? 16 : 18,
                    color: colors.textTertiary,
                  ),
                  onPressed: onDelete,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(
                    minWidth: compact ? 24 : 32,
                    minHeight: compact ? 24 : 32,
                  ),
                )
              else
                Icon(
                  Icons.download_rounded,
                  size: compact ? 14 : 16,
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
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
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

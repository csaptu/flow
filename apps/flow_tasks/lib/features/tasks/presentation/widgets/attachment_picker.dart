import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flow_tasks/core/theme/flow_theme.dart';

/// Result of attachment picker
class AttachmentPickerResult {
  final AttachmentPickerType type;
  final String? url; // For links
  final PlatformFile? file; // For files
  final XFile? image; // For images

  const AttachmentPickerResult({
    required this.type,
    this.url,
    this.file,
    this.image,
  });
}

enum AttachmentPickerType { link, file, image }

/// Bear-style minimalist attachment picker dialog
class AttachmentPicker extends StatefulWidget {
  final ValueChanged<AttachmentPickerResult> onAttachmentSelected;

  const AttachmentPicker({
    super.key,
    required this.onAttachmentSelected,
  });

  static Future<AttachmentPickerResult?> show(BuildContext context) async {
    return showDialog<AttachmentPickerResult>(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) => const _AttachmentPickerDialog(),
    );
  }

  @override
  State<AttachmentPicker> createState() => _AttachmentPickerState();
}

class _AttachmentPickerState extends State<AttachmentPicker> {
  @override
  Widget build(BuildContext context) {
    // This widget is kept for backwards compatibility
    // Use AttachmentPicker.show() for the new dialog
    return const SizedBox.shrink();
  }
}

class _AttachmentPickerDialog extends StatefulWidget {
  const _AttachmentPickerDialog();

  @override
  State<_AttachmentPickerDialog> createState() => _AttachmentPickerDialogState();
}

class _AttachmentPickerDialogState extends State<_AttachmentPickerDialog>
    with SingleTickerProviderStateMixin {
  bool _showLinkInput = false;
  final _urlController = TextEditingController();
  final _urlFocusNode = FocusNode();
  bool _isLoading = false;
  String? _urlError;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _urlFocusNode.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    setState(() => _isLoading = true);

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'pdf',
          'doc',
          'docx',
          'txt',
          'xls',
          'xlsx',
          'ppt',
          'pptx'
        ],
        allowMultiple: false,
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        Navigator.of(context).pop(AttachmentPickerResult(
          type: AttachmentPickerType.file,
          file: result.files.first,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick file: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _pickImage({bool fromCamera = false}) async {
    setState(() => _isLoading = true);

    try {
      final picker = ImagePicker();
      final XFile? image;

      if (fromCamera && !kIsWeb) {
        image = await picker.pickImage(source: ImageSource.camera);
      } else {
        image = await picker.pickImage(source: ImageSource.gallery);
      }

      if (image != null) {
        Navigator.of(context).pop(AttachmentPickerResult(
          type: AttachmentPickerType.image,
          image: image,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick image: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _submitUrl() {
    var url = _urlController.text.trim();

    if (url.isEmpty) {
      setState(() => _urlError = 'Please enter a URL');
      return;
    }

    // Add protocol if missing
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }

    // Basic URL validation
    try {
      final uri = Uri.parse(url);
      if (!uri.hasScheme || uri.host.isEmpty) {
        setState(() => _urlError = 'Please enter a valid URL');
        return;
      }
    } catch (_) {
      setState(() => _urlError = 'Please enter a valid URL');
      return;
    }

    Navigator.of(context).pop(AttachmentPickerResult(
      type: AttachmentPickerType.link,
      url: url,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final hasKeyboard = keyboardHeight > 0;

    // For dialogs without text input, center on full screen (ignore keyboard)
    // For dialogs with text input, center on visible area (above keyboard)
    Widget dialogContent = AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      child: _isLoading
          ? _buildLoading(colors)
          : _showLinkInput
              ? _buildLinkInput(colors)
              : _buildOptions(colors),
    );

    // When showing options (no text input) and keyboard is visible,
    // remove view insets so dialog centers on full screen
    if (!_showLinkInput && hasKeyboard) {
      return FadeTransition(
        opacity: _fadeAnimation,
        child: MediaQuery.removeViewInsets(
          context: context,
          removeBottom: true,
          child: Dialog(
            backgroundColor: colors.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            insetPadding: const EdgeInsets.all(24),
            child: dialogContent,
          ),
        ),
      );
    }

    // Default behavior for link input or when no keyboard
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Dialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.all(24),
        child: dialogContent,
      ),
    );
  }

  Widget _buildLoading(FlowColorScheme colors) {
    return Container(
      width: 200,
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: colors.primary),
          const SizedBox(height: 16),
          Text(
            'Loading...',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptions(FlowColorScheme colors) {
    return Container(
      width: 280,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Icon buttons row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _IconButton(
                icon: Icons.link_rounded,
                label: 'Link',
                color: Colors.blue,
                onTap: () {
                  setState(() => _showLinkInput = true);
                  Future.delayed(
                    const Duration(milliseconds: 100),
                    () => _urlFocusNode.requestFocus(),
                  );
                },
              ),
              _IconButton(
                icon: Icons.image_rounded,
                label: 'Image',
                color: Colors.green,
                onTap: () => _pickImage(),
              ),
              if (!kIsWeb)
                _IconButton(
                  icon: Icons.camera_alt_rounded,
                  label: 'Camera',
                  color: Colors.orange,
                  onTap: () => _pickImage(fromCamera: true),
                ),
              _IconButton(
                icon: Icons.insert_drive_file_rounded,
                label: 'Docs',
                color: Colors.purple,
                onTap: _pickFile,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLinkInput(FlowColorScheme colors) {
    return Container(
      width: 320,
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with back button
          Row(
            children: [
              GestureDetector(
                onTap: () => setState(() {
                  _showLinkInput = false;
                  _urlError = null;
                  _urlController.clear();
                }),
                child: Icon(
                  Icons.arrow_back_rounded,
                  size: 20,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Add link',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // URL input
          TextField(
            controller: _urlController,
            focusNode: _urlFocusNode,
            autofocus: true,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.done,
            style: TextStyle(
              fontSize: 14,
              color: colors.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: 'https://',
              hintStyle: TextStyle(color: colors.textPlaceholder),
              errorText: _urlError,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: colors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: colors.primary, width: 1.5),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: colors.error),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: colors.error, width: 1.5),
              ),
            ),
            onChanged: (_) {
              if (_urlError != null) {
                setState(() => _urlError = null);
              }
            },
            onSubmitted: (_) => _submitUrl(),
          ),
          const SizedBox(height: 16),

          // Action buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _submitUrl,
                style: FilledButton.styleFrom(
                  backgroundColor: colors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                ),
                child: const Text(
                  'Add',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _IconButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withOpacity(0.1),
            ),
            child: Icon(
              icon,
              size: 24,
              color: color,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flow_tasks/core/constants/app_spacing.dart';
import 'package:flow_tasks/core/theme/flow_theme.dart';

/// Result of an AI cooking dialog
enum AICookingResult {
  completed,  // AI action completed successfully
  stopped,    // User stopped the action
  timeout,    // Action timed out
  background, // User chose to continue in background
  error,      // An error occurred
}

/// Dialog that shows while AI is processing, with relaxing messages
/// and options to stop, continue in background, or wait for completion.
class AICookingDialog extends StatefulWidget {
  final Future<void> Function() action;
  final String actionName;
  final VoidCallback? onRevert; // Called if user stops after backend completed

  const AICookingDialog({
    super.key,
    required this.action,
    required this.actionName,
    this.onRevert,
  });

  /// Show the cooking dialog and run the AI action
  static Future<AICookingResult> show({
    required BuildContext context,
    required Future<void> Function() action,
    required String actionName,
    VoidCallback? onRevert,
  }) async {
    return await showDialog<AICookingResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AICookingDialog(
        action: action,
        actionName: actionName,
        onRevert: onRevert,
      ),
    ) ?? AICookingResult.stopped;
  }

  @override
  State<AICookingDialog> createState() => _AICookingDialogState();
}

class _AICookingDialogState extends State<AICookingDialog>
    with SingleTickerProviderStateMixin {
  // State
  bool _isProcessing = true;
  bool _isCompleted = false;
  bool _isStopped = false;
  bool _isTimedOut = false;
  bool _hasError = false;
  String? _errorMessage;
  int _countdownSeconds = 2;

  // Timers
  Timer? _timeoutTimer;
  Timer? _countdownTimer;
  Timer? _messageRotationTimer;

  // Animation
  late AnimationController _pulseController;

  // Relaxing messages that rotate
  int _currentMessageIndex = 0;
  static const _relaxingMessages = [
    "Take a breath, we're working on it...",
    "Sit back and relax...",
    "Good things take a moment...",
    "Almost there, stay calm...",
    "Let us handle the heavy lifting...",
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _startAction();
    _startMessageRotation();
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _countdownTimer?.cancel();
    _messageRotationTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _startAction() {
    // Start 15-second timeout
    _timeoutTimer = Timer(const Duration(seconds: 15), _handleTimeout);

    // Run the AI action
    widget.action().then((_) {
      if (mounted && !_isStopped) {
        // Allow completion even after timeout - the action finished successfully
        _handleCompletion();
      }
    }).catchError((error) {
      if (mounted && !_isStopped) {
        _handleError(error.toString());
      }
    });
  }

  void _startMessageRotation() {
    _messageRotationTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) {
        if (mounted && _isProcessing) {
          setState(() {
            _currentMessageIndex =
                (_currentMessageIndex + 1) % _relaxingMessages.length;
          });
        }
      },
    );
  }

  void _handleCompletion() {
    _timeoutTimer?.cancel();
    _messageRotationTimer?.cancel();

    setState(() {
      _isProcessing = false;
      _isCompleted = true;
    });

    // Start 2-second countdown before closing
    _countdownTimer = Timer.periodic(
      const Duration(seconds: 1),
      (timer) {
        if (mounted) {
          setState(() {
            _countdownSeconds--;
          });
          if (_countdownSeconds <= 0) {
            timer.cancel();
            Navigator.of(context).pop(AICookingResult.completed);
          }
        }
      },
    );
  }

  void _handleTimeout() {
    if (!mounted || _isCompleted || _isStopped) return;

    _messageRotationTimer?.cancel();

    setState(() {
      _isProcessing = false;
      _isTimedOut = true;
    });
  }

  void _handleError(String message) {
    _timeoutTimer?.cancel();
    _messageRotationTimer?.cancel();

    setState(() {
      _isProcessing = false;
      _hasError = true;
      _errorMessage = message;
    });
  }

  void _handleStop() {
    _timeoutTimer?.cancel();
    _countdownTimer?.cancel();
    _messageRotationTimer?.cancel();

    setState(() {
      _isStopped = true;
      _isProcessing = false;
    });

    // If the action already completed on backend, we need to revert
    if (_isCompleted && widget.onRevert != null) {
      widget.onRevert!();
    }

    Navigator.of(context).pop(AICookingResult.stopped);
  }

  void _handleBackground() {
    _timeoutTimer?.cancel();
    _countdownTimer?.cancel();
    _messageRotationTimer?.cancel();

    Navigator.of(context).pop(AICookingResult.background);
  }

  void _handleTimeoutDismiss() {
    Navigator.of(context).pop(AICookingResult.timeout);
  }

  void _handleErrorDismiss() {
    Navigator.of(context).pop(AICookingResult.error);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    Widget dialog = Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: FlowSpacing.dialogMaxWidth),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isProcessing) _buildProcessingState(colors),
              if (_isCompleted && !_isStopped) _buildCompletedState(colors),
              if (_isTimedOut) _buildTimeoutState(colors),
              if (_hasError) _buildErrorState(colors),
            ],
          ),
        ),
      ),
    );

    // This dialog has no text input, so center on full screen (ignore keyboard)
    if (keyboardHeight > 0) {
      return MediaQuery.removeViewInsets(
        context: context,
        removeBottom: true,
        child: dialog,
      );
    }

    return dialog;
  }

  Widget _buildProcessingState(FlowColorScheme colors) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Animated cooking icon
        AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            return Transform.scale(
              scale: 1.0 + (_pulseController.value * 0.1),
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: colors.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.auto_awesome,
                  size: 32,
                  color: colors.primary,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 20),

        // Relaxing message
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          child: Text(
            _relaxingMessages[_currentMessageIndex],
            key: ValueKey(_currentMessageIndex),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: colors.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 8),

        // Action name subtitle
        Text(
          widget.actionName,
          style: TextStyle(
            fontSize: 13,
            color: colors.textTertiary,
          ),
        ),
        const SizedBox(height: 24),

        // Progress indicator
        LinearProgressIndicator(
          backgroundColor: colors.divider,
          valueColor: AlwaysStoppedAnimation(colors.primary),
        ),
        const SizedBox(height: 24),

        // Action buttons
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Stop button
            TextButton.icon(
              onPressed: _handleStop,
              icon: Icon(Icons.stop_rounded, size: 18, color: colors.error),
              label: Text(
                'Stop',
                style: TextStyle(color: colors.error),
              ),
            ),
            const SizedBox(width: 16),

            // Continue in background button
            TextButton.icon(
              onPressed: _handleBackground,
              icon: Icon(Icons.open_in_new_rounded, size: 18, color: colors.textSecondary),
              label: Text(
                'Continue in background',
                style: TextStyle(color: colors.textSecondary),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCompletedState(FlowColorScheme colors) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Success icon
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: const Color(0xFF10B981).withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_rounded,
            size: 32,
            color: Color(0xFF10B981),
          ),
        ),
        const SizedBox(height: 20),

        // Completion message
        Text(
          'All done!',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),

        // Countdown
        Text(
          'Closing in $_countdownSeconds...',
          style: TextStyle(
            fontSize: 13,
            color: colors.textTertiary,
          ),
        ),
        const SizedBox(height: 24),

        // Stop button (to revert if user changed mind)
        TextButton.icon(
          onPressed: _handleStop,
          icon: Icon(Icons.undo_rounded, size: 18, color: colors.textSecondary),
          label: Text(
            'Undo changes',
            style: TextStyle(color: colors.textSecondary),
          ),
        ),
      ],
    );
  }

  Widget _buildTimeoutState(FlowColorScheme colors) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Warning icon
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: colors.warning.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.hourglass_empty_rounded,
            size: 32,
            color: colors.warning,
          ),
        ),
        const SizedBox(height: 20),

        // Timeout message
        Text(
          'Taking longer than expected',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),

        Text(
          'You can close this and check back later.\nChanges will appear when ready.',
          style: TextStyle(
            fontSize: 13,
            color: colors.textTertiary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),

        // Action buttons
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(
              onPressed: _handleStop,
              child: Text(
                'Cancel',
                style: TextStyle(color: colors.error),
              ),
            ),
            const SizedBox(width: 16),
            FilledButton(
              onPressed: _handleTimeoutDismiss,
              style: FilledButton.styleFrom(
                backgroundColor: colors.primary,
              ),
              child: const Text('Close & continue'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildErrorState(FlowColorScheme colors) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Error icon
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: colors.error.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.error_outline_rounded,
            size: 32,
            color: colors.error,
          ),
        ),
        const SizedBox(height: 20),

        // Error message
        Text(
          'Something went wrong',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),

        Text(
          _errorMessage ?? 'Please try again later.',
          style: TextStyle(
            fontSize: 13,
            color: colors.textTertiary,
          ),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 24),

        FilledButton(
          onPressed: _handleErrorDismiss,
          style: FilledButton.styleFrom(
            backgroundColor: colors.primary,
          ),
          child: const Text('OK'),
        ),
      ],
    );
  }
}

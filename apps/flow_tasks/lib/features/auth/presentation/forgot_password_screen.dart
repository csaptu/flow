import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flow_tasks/core/constants/app_colors.dart';
import 'package:flow_tasks/core/constants/app_spacing.dart';
import 'package:flow_tasks/core/providers/providers.dart';

enum _ResetStep { email, code, password }

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  final _codeControllers = List.generate(6, (_) => TextEditingController());
  final _codeFocusNodes = List.generate(6, (_) => FocusNode());
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  _ResetStep _currentStep = _ResetStep.email;
  bool _isLoading = false;
  String? _error;
  int _secondsRemaining = 0;
  Timer? _timer;

  @override
  void dispose() {
    _emailController.dispose();
    for (final c in _codeControllers) {
      c.dispose();
    }
    for (final f in _codeFocusNodes) {
      f.dispose();
    }
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  String get _code => _codeControllers.map((c) => c.text).join();

  void _startTimer(int seconds) {
    _secondsRemaining = seconds;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        setState(() => _secondsRemaining--);
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _sendCode() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Please enter a valid email address');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final authService = ref.read(authServiceProvider);
      final expiresIn = await authService.forgotPassword(email);
      if (mounted) {
        setState(() {
          _currentStep = _ResetStep.code;
          _isLoading = false;
        });
        _startTimer(expiresIn);
        // Focus first code input
        _codeFocusNodes[0].requestFocus();
      }
    } catch (e) {
      if (mounted) {
        // Still advance to code step (security: don't reveal if email exists)
        setState(() {
          _currentStep = _ResetStep.code;
          _isLoading = false;
        });
        _startTimer(600); // Default 10 min
        _codeFocusNodes[0].requestFocus();
      }
    }
  }

  Future<void> _verifyCode() async {
    if (_code.length != 6) {
      setState(() => _error = 'Please enter the 6-digit code');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final authService = ref.read(authServiceProvider);
      await authService.verifyResetCode(
        email: _emailController.text.trim(),
        code: _code,
      );
      if (mounted) {
        setState(() {
          _currentStep = _ResetStep.password;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        String message = e.toString();
        if (message.contains('attempts remaining')) {
          // Extract the remaining attempts message
          final match = RegExp(r'(\d+) attempts remaining').firstMatch(message);
          if (match != null) {
            message = 'Invalid code. ${match.group(1)} attempts remaining.';
          }
        } else if (message.contains('too many')) {
          message = 'Too many attempts. Please request a new code.';
        } else {
          message = 'Invalid or expired code';
        }
        setState(() {
          _error = message;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _resetPassword() async {
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (password.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters');
      return;
    }

    if (password != confirmPassword) {
      setState(() => _error = 'Passwords do not match');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final authService = ref.read(authServiceProvider);
      await authService.resetPassword(
        email: _emailController.text.trim(),
        code: _code,
        newPassword: password,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Password reset successful! Please log in.'),
            backgroundColor: Colors.green,
          ),
        );
        context.go('/login');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to reset password. Please try again.';
          _isLoading = false;
        });
      }
    }
  }

  void _onCodeChanged(int index, String value) {
    if (value.length == 1 && index < 5) {
      _codeFocusNodes[index + 1].requestFocus();
    }
    // Auto-submit when all 6 digits entered
    if (_code.length == 6) {
      _verifyCode();
    }
  }

  void _onCodeBackspace(int index) {
    if (_codeControllers[index].text.isEmpty && index > 0) {
      _codeFocusNodes[index - 1].requestFocus();
      _codeControllers[index - 1].clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reset Password'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_currentStep == _ResetStep.email) {
              context.go('/login');
            } else {
              setState(() {
                _currentStep = _ResetStep.email;
                _error = null;
                for (final c in _codeControllers) {
                  c.clear();
                }
              });
            }
          },
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: FlowSpacing.screenPadding,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: FlowSpacing.xl),

                    // Step indicator
                    _buildStepIndicator(),
                    const SizedBox(height: FlowSpacing.xl),

                    // Error message
                    if (_error != null) ...[
                      Container(
                        padding: const EdgeInsets.all(FlowSpacing.md),
                        decoration: BoxDecoration(
                          color: FlowColors.error.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(FlowSpacing.radiusSm),
                        ),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: FlowColors.error),
                        ),
                      ),
                      const SizedBox(height: FlowSpacing.md),
                    ],

                    // Current step content
                    if (_currentStep == _ResetStep.email) _buildEmailStep(),
                    if (_currentStep == _ResetStep.code) _buildCodeStep(),
                    if (_currentStep == _ResetStep.password) _buildPasswordStep(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildStepDot(0, _currentStep.index >= 0),
        _buildStepLine(_currentStep.index >= 1),
        _buildStepDot(1, _currentStep.index >= 1),
        _buildStepLine(_currentStep.index >= 2),
        _buildStepDot(2, _currentStep.index >= 2),
      ],
    );
  }

  Widget _buildStepDot(int step, bool active) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? FlowColors.primary : Colors.grey.shade300,
      ),
      child: Center(
        child: Text(
          '${step + 1}',
          style: TextStyle(
            color: active ? Colors.white : Colors.grey.shade600,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildStepLine(bool active) {
    return Container(
      width: 40,
      height: 2,
      color: active ? FlowColors.primary : Colors.grey.shade300,
    );
  }

  Widget _buildEmailStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Enter your email',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: FlowSpacing.sm),
        Text(
          'We\'ll send you a 6-digit code to reset your password.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: FlowColors.lightTextSecondary,
              ),
        ),
        const SizedBox(height: FlowSpacing.lg),
        TextFormField(
          controller: _emailController,
          decoration: const InputDecoration(
            labelText: 'Email',
            prefixIcon: Icon(Icons.email_outlined),
          ),
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _sendCode(),
          autofocus: true,
        ),
        const SizedBox(height: FlowSpacing.lg),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _isLoading ? null : _sendCode,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Send Code'),
          ),
        ),
      ],
    );
  }

  Widget _buildCodeStep() {
    final minutes = _secondsRemaining ~/ 60;
    final seconds = _secondsRemaining % 60;
    final timeString = '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Enter verification code',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: FlowSpacing.sm),
        Text(
          'We sent a code to ${_emailController.text}',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: FlowColors.lightTextSecondary,
              ),
        ),
        const SizedBox(height: FlowSpacing.lg),

        // 6-digit code input
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(6, (index) {
            return SizedBox(
              width: 48,
              child: KeyboardListener(
                focusNode: FocusNode(),
                onKeyEvent: (event) {
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.backspace) {
                    _onCodeBackspace(index);
                  }
                },
                child: TextFormField(
                  controller: _codeControllers[index],
                  focusNode: _codeFocusNodes[index],
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  maxLength: 1,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  decoration: const InputDecoration(
                    counterText: '',
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (value) => _onCodeChanged(index, value),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: FlowSpacing.md),

        // Timer
        Center(
          child: Text(
            _secondsRemaining > 0
                ? 'Code expires in $timeString'
                : 'Code expired',
            style: TextStyle(
              color: _secondsRemaining > 60
                  ? FlowColors.lightTextSecondary
                  : FlowColors.error,
            ),
          ),
        ),
        const SizedBox(height: FlowSpacing.lg),

        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _isLoading || _code.length != 6 ? null : _verifyCode,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Verify Code'),
          ),
        ),
        const SizedBox(height: FlowSpacing.md),

        // Resend code
        Center(
          child: TextButton(
            onPressed: _secondsRemaining > 0 ? null : () {
              setState(() {
                _currentStep = _ResetStep.email;
                for (final c in _codeControllers) {
                  c.clear();
                }
              });
            },
            child: Text(
              _secondsRemaining > 0
                  ? 'Resend code in $timeString'
                  : 'Resend code',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Create new password',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: FlowSpacing.sm),
        Text(
          'Your password must be at least 8 characters.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: FlowColors.lightTextSecondary,
              ),
        ),
        const SizedBox(height: FlowSpacing.lg),
        TextFormField(
          controller: _passwordController,
          decoration: const InputDecoration(
            labelText: 'New Password',
            prefixIcon: Icon(Icons.lock_outline),
          ),
          obscureText: true,
          textInputAction: TextInputAction.next,
          autofocus: true,
        ),
        const SizedBox(height: FlowSpacing.md),
        TextFormField(
          controller: _confirmPasswordController,
          decoration: const InputDecoration(
            labelText: 'Confirm Password',
            prefixIcon: Icon(Icons.lock_outline),
          ),
          obscureText: true,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _resetPassword(),
        ),
        const SizedBox(height: FlowSpacing.lg),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _isLoading ? null : _resetPassword,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Reset Password'),
          ),
        ),
      ],
    );
  }
}

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flow_tasks/core/constants/app_colors.dart';
import 'package:flow_tasks/core/constants/app_spacing.dart';
import 'package:flow_tasks/core/providers/providers.dart';

// Dev accounts for quick login (only shown in debug mode)
const _devAccounts = [
  ('tupham', 'quangtu.pham@gmail.com'),
  ('prepedu', 'tupham@prepedu.com'),
];

class LoginScreen extends ConsumerStatefulWidget {
  final bool isRegister;

  const LoginScreen({super.key, this.isRegister = false});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _nameController = TextEditingController();
  final _codeControllers = List.generate(6, (_) => TextEditingController());
  final _codeFocusNodes = List.generate(6, (_) => FocusNode());

  bool _isRegister = false;
  bool _isVerifying = false;
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  String? _error;
  int _secondsRemaining = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _isRegister = widget.isRegister;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _nameController.dispose();
    for (final c in _codeControllers) {
      c.dispose();
    }
    for (final f in _codeFocusNodes) {
      f.dispose();
    }
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final authNotifier = ref.read(authStateProvider.notifier);
      if (_isRegister) {
        // Registration now sends verification code
        final expiresIn = await authNotifier.startRegistration(
          _emailController.text.trim(),
          _passwordController.text,
          _nameController.text.trim(),
        );
        if (mounted) {
          setState(() {
            _isVerifying = true;
            _isLoading = false;
          });
          _startTimer(expiresIn);
          _codeFocusNodes[0].requestFocus();
        }
      } else {
        await authNotifier.login(
          _emailController.text.trim(),
          _passwordController.text,
        );
        if (mounted) {
          context.go('/');
        }
      }
    } catch (e) {
      String errorMessage = e.toString();
      if (errorMessage.contains('401') || errorMessage.contains('Unauthorized')) {
        errorMessage = 'Invalid email or password. Please try again.';
      } else if (errorMessage.contains('network') || errorMessage.contains('SocketException')) {
        errorMessage = 'Network error. Please check your connection.';
      } else if (errorMessage.contains('Conflict') || errorMessage.contains('already registered')) {
        errorMessage = 'This email is already registered. Please sign in.';
      }
      setState(() => _error = errorMessage);
    } finally {
      if (mounted && !_isVerifying) {
        setState(() => _isLoading = false);
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
      final authNotifier = ref.read(authStateProvider.notifier);
      await authNotifier.completeRegistration(
        _emailController.text.trim(),
        _code,
      );
      if (mounted) {
        context.go('/');
      }
    } catch (e) {
      if (mounted) {
        String message = e.toString();
        if (message.contains('attempts remaining')) {
          final match = RegExp(r'(\d+) attempts remaining').firstMatch(message);
          if (match != null) {
            message = 'Invalid code. ${match.group(1)} attempts remaining.';
          }
        } else if (message.contains('too many')) {
          message = 'Too many attempts. Please register again.';
          // Reset to registration form
          setState(() {
            _isVerifying = false;
            for (final c in _codeControllers) {
              c.clear();
            }
          });
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

  Future<void> _resendCode() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final authNotifier = ref.read(authStateProvider.notifier);
      final expiresIn = await authNotifier.resendVerificationCode(
        _emailController.text.trim(),
      );
      if (mounted) {
        setState(() => _isLoading = false);
        _startTimer(expiresIn);
        for (final c in _codeControllers) {
          c.clear();
        }
        _codeFocusNodes[0].requestFocus();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to resend code. Please try again.';
          _isLoading = false;
        });
      }
    }
  }

  void _onCodeChanged(int index, String value) {
    if (value.length == 1 && index < 5) {
      _codeFocusNodes[index + 1].requestFocus();
    }
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

  void _forgotPassword() {
    context.go('/forgot-password');
  }

  Future<void> _devLogin(String email) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final authNotifier = ref.read(authStateProvider.notifier);
      await authNotifier.devLogin(email);
      if (mounted) {
        context.go('/');
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    if (!mounted) return;
    setState(() {
      _isGoogleLoading = true;
      _error = null;
    });

    try {
      final authNotifier = ref.read(authStateProvider.notifier);
      await authNotifier.loginWithGoogle();
      final authState = ref.read(authStateProvider);
      if (mounted && authState.status == AuthStatus.authenticated) {
        context.go('/');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isGoogleLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isVerifying) {
      return _buildVerificationScreen();
    }
    return _buildLoginRegisterScreen();
  }

  Widget _buildVerificationScreen() {
    final minutes = _secondsRemaining ~/ 60;
    final seconds = _secondsRemaining % 60;
    final timeString = '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify Email'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            setState(() {
              _isVerifying = false;
              _error = null;
              for (final c in _codeControllers) {
                c.clear();
              }
            });
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
                    const SizedBox(height: FlowSpacing.xl),

                    // Error message
                    if (_error != null) ...[
                      Container(
                        padding: const EdgeInsets.all(FlowSpacing.md),
                        decoration: BoxDecoration(
                          color: FlowColors.error.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(FlowSpacing.radiusSm),
                        ),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: FlowColors.error),
                        ),
                      ),
                      const SizedBox(height: FlowSpacing.md),
                    ],

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

                    // Verify button
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
                            : const Text('Verify & Create Account'),
                      ),
                    ),
                    const SizedBox(height: FlowSpacing.md),

                    // Resend code
                    Center(
                      child: TextButton(
                        onPressed: _secondsRemaining > 0 || _isLoading ? null : _resendCode,
                        child: Text(
                          _secondsRemaining > 0
                              ? 'Resend code in $timeString'
                              : 'Resend code',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginRegisterScreen() {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Center(
            child: Padding(
              padding: FlowSpacing.screenPadding,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Logo/Title
                      const Icon(
                        Icons.check_circle_outline,
                        size: 64,
                        color: FlowColors.primary,
                      ),
                      const SizedBox(height: FlowSpacing.md),
                      Text(
                        'Flow Tasks',
                        style: Theme.of(context).textTheme.displayLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: FlowSpacing.xs),
                      Text(
                        _isRegister ? 'Create your account' : 'Welcome back',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: FlowColors.lightTextSecondary,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: FlowSpacing.xxl),

                      // Error message
                      if (_error != null) ...[
                        Container(
                          padding: const EdgeInsets.all(FlowSpacing.md),
                          decoration: BoxDecoration(
                            color: FlowColors.error.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(FlowSpacing.radiusSm),
                          ),
                          child: Text(
                            _error!,
                            style: const TextStyle(color: FlowColors.error),
                          ),
                        ),
                        const SizedBox(height: FlowSpacing.md),
                      ],

                      // Name field (register only)
                      if (_isRegister) ...[
                        TextFormField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: 'Name',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter your name';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: FlowSpacing.md),
                      ],

                      // Email field
                      TextFormField(
                        controller: _emailController,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        textInputAction: TextInputAction.next,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your email';
                          }
                          if (!value.contains('@')) {
                            return 'Please enter a valid email';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: FlowSpacing.md),

                      // Password field
                      TextFormField(
                        controller: _passwordController,
                        decoration: const InputDecoration(
                          labelText: 'Password',
                          prefixIcon: Icon(Icons.lock_outline),
                        ),
                        obscureText: true,
                        textInputAction: _isRegister ? TextInputAction.next : TextInputAction.done,
                        onFieldSubmitted: _isRegister ? null : (_) => _submit(),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your password';
                          }
                          if (_isRegister) {
                            if (value.length < 8) {
                              return 'Password must be at least 8 characters';
                            }
                            if (!value.contains(RegExp(r'[A-Z]'))) {
                              return 'Password must contain at least 1 uppercase letter';
                            }
                            if (!value.contains(RegExp(r'[a-z]'))) {
                              return 'Password must contain at least 1 lowercase letter';
                            }
                            if (!value.contains(RegExp(r'[0-9]'))) {
                              return 'Password must contain at least 1 number';
                            }
                          }
                          return null;
                        },
                      ),

                      // Confirm password field (register only)
                      if (_isRegister) ...[
                        const SizedBox(height: FlowSpacing.md),
                        TextFormField(
                          controller: _confirmPasswordController,
                          decoration: const InputDecoration(
                            labelText: 'Confirm Password',
                            prefixIcon: Icon(Icons.lock_outline),
                          ),
                          obscureText: true,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _submit(),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please confirm your password';
                            }
                            if (value != _passwordController.text) {
                              return 'Passwords do not match';
                            }
                            return null;
                          },
                        ),
                      ],

                      // Forgot password link (login only)
                      if (!_isRegister) ...[
                        const SizedBox(height: FlowSpacing.xs),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _forgotPassword,
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              'Forgot password?',
                              style: TextStyle(
                                fontSize: 13,
                                color: FlowColors.primary.withValues(alpha: 0.8),
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: FlowSpacing.lg),

                      // Submit button
                      FilledButton(
                        onPressed: _isLoading ? null : _submit,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(FlowSpacing.radiusSm),
                          ),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(_isRegister ? 'Create Account' : 'Sign In'),
                      ),
                      const SizedBox(height: FlowSpacing.lg),

                      // Divider
                      Row(
                        children: [
                          const Expanded(child: Divider()),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: FlowSpacing.md),
                            child: Text(
                              'or',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: FlowColors.lightTextSecondary,
                                  ),
                            ),
                          ),
                          const Expanded(child: Divider()),
                        ],
                      ),
                      const SizedBox(height: FlowSpacing.lg),

                      // Google sign-in button
                      OutlinedButton.icon(
                        onPressed: _isGoogleLoading ? null : _signInWithGoogle,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(FlowSpacing.radiusSm),
                          ),
                        ),
                        icon: _isGoogleLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text(
                                'G',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF757575),
                                ),
                              ),
                        label: const Text('Continue with Google'),
                      ),
                      const SizedBox(height: FlowSpacing.md),

                      // Toggle login/register
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _isRegister = !_isRegister;
                            _error = null;
                          });
                        },
                        child: Text(
                          _isRegister
                              ? 'Already have an account? Sign in'
                              : "Don't have an account? Create one",
                        ),
                      ),

                      // Dev login buttons (debug only)
                      if (kDebugMode) ...[
                        const SizedBox(height: FlowSpacing.lg),
                        const Divider(),
                        const SizedBox(height: FlowSpacing.sm),
                        Text(
                          'Dev Login',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: FlowColors.lightTextSecondary,
                              ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: FlowSpacing.sm),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (final account in _devAccounts) ...[
                              TextButton(
                                onPressed: _isLoading ? null : () => _devLogin(account.$1),
                                child: Text(account.$2),
                              ),
                            ],
                          ],
                        ),
                      ],
                      const SizedBox(height: FlowSpacing.xxl),

                      // Footer links
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          TextButton(
                            onPressed: () => context.push('/pricing'),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              'Pricing',
                              style: TextStyle(
                                fontSize: 13,
                                color: FlowColors.lightTextSecondary.withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                          Text(
                            ' · ',
                            style: TextStyle(
                              color: FlowColors.lightTextSecondary.withValues(alpha: 0.5),
                            ),
                          ),
                          TextButton(
                            onPressed: () => context.push('/terms'),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              'Terms',
                              style: TextStyle(
                                fontSize: 13,
                                color: FlowColors.lightTextSecondary.withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                          Text(
                            ' · ',
                            style: TextStyle(
                              color: FlowColors.lightTextSecondary.withValues(alpha: 0.5),
                            ),
                          ),
                          TextButton(
                            onPressed: () => context.push('/privacy'),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              'Privacy',
                              style: TextStyle(
                                fontSize: 13,
                                color: FlowColors.lightTextSecondary.withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: FlowSpacing.md),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

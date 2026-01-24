import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flow_tasks/core/constants/app_colors.dart';
import 'package:flow_tasks/core/constants/app_spacing.dart';
import 'package:flow_tasks/core/providers/providers.dart';

// Dev accounts for quick login (only shown in debug mode)
// Uses aliases that the server resolves to real emails
const _devAccounts = [
  ('tupham', 'Tu Pham'),  // -> quangtu.pham@gmail.com
  ('alice', 'Alice'),      // -> alice@prepedu.com
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
  final _nameController = TextEditingController();

  bool _isRegister = false;
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _isRegister = widget.isRegister;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
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
        await authNotifier.register(
          _emailController.text,
          _passwordController.text,
          _nameController.text,
        );
      } else {
        await authNotifier.login(
          _emailController.text,
          _passwordController.text,
        );
      }
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
      // Only navigate if login actually succeeded
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
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
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
                          color: FlowColors.error.withOpacity(0.1),
                          borderRadius:
                              BorderRadius.circular(FlowSpacing.radiusSm),
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
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter your password';
                        }
                        if (_isRegister && value.length < 8) {
                          return 'Password must be at least 8 characters';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: FlowSpacing.lg),

                    // Submit button
                    FilledButton(
                      onPressed: _isLoading ? null : _submit,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(FlowSpacing.radiusSm),
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
                          padding: const EdgeInsets.symmetric(
                              horizontal: FlowSpacing.md),
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
                          borderRadius:
                              BorderRadius.circular(FlowSpacing.radiusSm),
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
                    // Version info
                    Text(
                      'v2026-01-24 16:00 GMT+7',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: FlowColors.lightTextSecondary.withOpacity(0.5),
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Subscription auto-expiry; Mobile: toolbar above keyboard, dialogs centered',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: FlowColors.lightTextSecondary.withOpacity(0.4),
                            fontSize: 10,
                          ),
                      textAlign: TextAlign.center,
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
}

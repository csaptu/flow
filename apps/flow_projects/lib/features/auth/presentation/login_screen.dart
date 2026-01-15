import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flow_projects/core/constants/app_colors.dart';
import 'package:flow_projects/core/constants/app_spacing.dart';
import 'package:flow_projects/core/providers/providers.dart';

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
                      Icons.account_tree_rounded,
                      size: 64,
                      color: FlowColors.primary,
                    ),
                    const SizedBox(height: FlowSpacing.md),
                    Text(
                      'Flow Projects',
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

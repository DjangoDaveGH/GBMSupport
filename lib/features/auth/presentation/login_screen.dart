import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hyport/core/auth/auth_providers.dart';
import 'package:hyport/core/responsive.dart';
import 'package:hyport/core/theme/app_theme.dart';
import 'package:hyport/core/widgets/hex_pattern.dart';

/// No self-signup in the MVP — accounts are admin-provisioned (see
/// Section 10), though users can submit a Request Access form for staff to
/// review. Matches the reference Login screen exactly: plain white
/// background, no gradient panel — branding lives on the Splash/Welcome
/// screens before this one.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _submitting = false;
  bool _obscure = true;
  bool _rememberMe = true;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider).signIn(
            email: _emailController.text.trim(),
            password: _passwordController.text,
          );
      // Navigation is handled by the router's redirect once auth state
      // changes. Deliberately leave _submitting true on success — the
      // profile fetch the redirect waits on takes a beat, and resetting it
      // here would flash the form back to idle for that beat before the
      // screen is replaced.
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() {
          _error = _messageFor(e.code);
          _submitting = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Something went wrong. Please try again.';
          _submitting = false;
        });
      }
    }
  }

  String _messageFor(String code) {
    switch (code) {
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'user-disabled':
        return 'This account has been disabled. Contact PFM-Systems.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait and try again.';
      default:
        return 'Sign-in failed ($code).';
    }
  }

  @override
  Widget build(BuildContext context) {
    return isDesktopWidth(context) ? _buildDesktopLayout(context) : _buildMobileLayout(context);
  }

  Widget _buildMobileLayout(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: _buildForm(context, greeting: 'Welcome Back 👋', subtitle: 'Please login to continue'),
            ),
          ),
        ),
      ),
    );
  }

  /// Phase 5 mockup screen 29 — a split hero/form panel instead of the
  /// mobile app's plain white screen. Same `_formKey`/controllers/`_submit`
  /// underneath; only the surrounding chrome differs.
  Widget _buildDesktopLayout(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Row(
        children: [
          Expanded(
            child: Container(
              color: AppTheme.navyDarkest,
              child: Stack(
                children: [
                  const Positioned.fill(child: HexPatternBackground(opacity: 0.05)),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(48),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.asset('assets/images/mof_logo.png', width: 104, height: 104),
                          const SizedBox(height: 28),
                          Text(
                            'GBMS\nSUPPORT CENTRE',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: AppTheme.fontFamily,
                              color: AppTheme.gold,
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Enterprise Management Portal',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 14.5),
                          ),
                          const SizedBox(height: 64),
                          Text(
                            'PFMSD Applications Unit',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12.5, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '© ${DateTime.now().year} Ministry of Finance. All rights reserved.',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11.5),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(48),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: _buildForm(context, greeting: 'Welcome Back', subtitle: 'Please sign in to your account'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm(BuildContext context, {required String greeting, required String subtitle}) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(greeting, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black54),
          ),
          const SizedBox(height: AppSpacing.xxl),
          Text('Email Address', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.black54)),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(hintText: 'youremail@mda.gov.gh'),
                      validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text('Password', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.black54)),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        suffixIcon: IconButton(
                          icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (v) => (v == null || v.isEmpty) ? 'Enter your password' : null,
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        InkWell(
                          onTap: () => setState(() => _rememberMe = !_rememberMe),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Checkbox(value: _rememberMe, onChanged: (v) => setState(() => _rememberMe = v ?? true)),
                              const Text('Remember Me'),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () => context.push('/forgot-password'),
                          child: const Text('Forgot Password?'),
                        ),
                      ],
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 200),
                      child: _error == null
                          ? const SizedBox(width: double.infinity)
                          : Padding(
                              padding: const EdgeInsets.only(top: AppSpacing.sm),
                              child: Container(
                                padding: const EdgeInsets.all(AppSpacing.md),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.error.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(AppRadius.md),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.error_outline_rounded, size: 18, color: Theme.of(context).colorScheme.error),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _error!,
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _submitting ? null : _submit,
                        child: _submitting
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('LOGIN'),
                      ),
                    ),
        ],
      ),
    );
  }
}

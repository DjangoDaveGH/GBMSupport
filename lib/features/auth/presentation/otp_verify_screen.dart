import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hyport/core/auth/auth_providers.dart';
import 'package:hyport/core/theme/app_theme.dart';

/// The two-factor login step, shown once per app session for any account
/// with 2FA turned on (see SettingsScreen). Real email dispatch needs a
/// Cloud Function, which is blocked on the Blaze plan — see
/// OtpRepository's doc comment and DECISIONS.md. Until that's resolved,
/// the freshly-generated code is displayed directly on this screen instead
/// of being emailed, and that's stated plainly in the UI rather than
/// pretended away. Matches mockup screen 4 (6 individual digit boxes,
/// countdown-gated resend) with that one honest addition.
class OtpVerifyScreen extends ConsumerStatefulWidget {
  const OtpVerifyScreen({super.key});

  @override
  ConsumerState<OtpVerifyScreen> createState() => _OtpVerifyScreenState();
}

const _resendCooldownSeconds = 45;

class _OtpVerifyScreenState extends ConsumerState<OtpVerifyScreen> {
  final List<TextEditingController> _digitControllers = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _digitFocusNodes = List.generate(6, (_) => FocusNode());
  String? _displayedCode;
  String? _error;
  bool _generating = true;
  bool _verifying = false;
  Timer? _cooldownTimer;
  int _cooldownRemaining = _resendCooldownSeconds;

  @override
  void initState() {
    super.initState();
    _generate();
  }

  @override
  void dispose() {
    for (final c in _digitControllers) {
      c.dispose();
    }
    for (final f in _digitFocusNodes) {
      f.dispose();
    }
    _cooldownTimer?.cancel();
    super.dispose();
  }

  String? get _uid => ref.read(authStateChangesProvider).valueOrNull?.uid;

  String get _enteredCode => _digitControllers.map((c) => c.text).join();

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _cooldownRemaining = _resendCooldownSeconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      if (_cooldownRemaining <= 1) {
        timer.cancel();
        setState(() => _cooldownRemaining = 0);
      } else {
        setState(() => _cooldownRemaining--);
      }
    });
  }

  Future<void> _generate() async {
    final uid = _uid;
    if (uid == null) return;
    setState(() {
      _generating = true;
      _error = null;
    });
    for (final c in _digitControllers) {
      c.clear();
    }
    final code = await ref.read(otpRepositoryProvider).generate(uid);
    if (mounted) {
      setState(() {
        _displayedCode = code;
        _generating = false;
      });
      _startCooldown();
      _digitFocusNodes.first.requestFocus();
    }
  }

  Future<void> _verify() async {
    final uid = _uid;
    if (uid == null || _enteredCode.length != 6) return;
    setState(() {
      _verifying = true;
      _error = null;
    });
    final ok = await ref.read(otpRepositoryProvider).verify(uid, _enteredCode);
    if (!mounted) return;
    if (ok) {
      ref.read(otpVerifiedProvider(uid).notifier).state = true;
      context.go('/home');
    } else {
      setState(() {
        _verifying = false;
        _error = 'That code is incorrect or has expired. Tap Resend for a new one.';
      });
    }
  }

  void _onDigitChanged(int index, String value) {
    if (value.length > 1) {
      // Handles a pasted 6-digit code landing in one box.
      final digits = value.replaceAll(RegExp(r'\D'), '').split('');
      for (var i = 0; i < 6; i++) {
        _digitControllers[i].text = i < digits.length ? digits[i] : '';
      }
      final lastFilled = digits.length.clamp(0, 6) - 1;
      if (lastFilled >= 0 && lastFilled < 5) {
        _digitFocusNodes[lastFilled + 1].requestFocus();
      } else {
        _digitFocusNodes[5].unfocus();
      }
    } else if (value.isNotEmpty && index < 5) {
      _digitFocusNodes[index + 1].requestFocus();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final email = ref.watch(currentAppUserProvider).valueOrNull?.email;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => ref.read(authServiceProvider).signOut(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Image.asset('assets/images/illustration_otp.png', width: 140, height: 140),
                ),
              ),
              Text('Verify Your Account', style: textTheme.headlineSmall, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(
                email == null ? 'Enter the 6-digit code to verify your identity.' : 'Enter the 6-digit code for $email.',
                style: textTheme.bodyMedium?.copyWith(color: Colors.black54),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.gold.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppTheme.gold.withValues(alpha: 0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline_rounded, size: 18, color: AppTheme.gold),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Email delivery isn\'t active yet, so your code is shown here for now:',
                            style: textTheme.bodySmall,
                          ),
                          const SizedBox(height: 8),
                          _generating
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Text(
                                  _displayedCode ?? '——————',
                                  style: textTheme.headlineSmall?.copyWith(
                                    color: AppTheme.navy,
                                    letterSpacing: 6,
                                    fontFeatures: const [FontFeature.tabularFigures()],
                                  ),
                                ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(6, (i) => _DigitBox(
                      controller: _digitControllers[i],
                      focusNode: _digitFocusNodes[i],
                      onChanged: (v) => _onDigitChanged(i, v),
                      onBackspaceEmpty: () {
                        if (i > 0) _digitFocusNodes[i - 1].requestFocus();
                      },
                    )),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: (_verifying || _enteredCode.length != 6) ? null : _verify,
                  child: _verifying
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('VERIFY'),
                ),
              ),
              const SizedBox(height: 20),
              Center(
                child: Column(
                  children: [
                    Text('Didn\'t receive code?', style: textTheme.bodySmall),
                    TextButton(
                      onPressed: (_generating || _cooldownRemaining > 0) ? null : _generate,
                      child: Text(
                        _cooldownRemaining > 0
                            ? 'Resend Code (00:${_cooldownRemaining.toString().padLeft(2, '0')})'
                            : 'Resend Code',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DigitBox extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onBackspaceEmpty;

  const _DigitBox({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onBackspaceEmpty,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 52,
      child: KeyboardListener(
        focusNode: FocusNode(skipTraversal: true, canRequestFocus: false),
        onKeyEvent: (event) {
          if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.backspace && controller.text.isEmpty) {
            onBackspaceEmpty();
          }
        },
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          maxLength: 1,
          style: Theme.of(context).textTheme.headlineSmall,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(counterText: '', contentPadding: EdgeInsets.zero),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

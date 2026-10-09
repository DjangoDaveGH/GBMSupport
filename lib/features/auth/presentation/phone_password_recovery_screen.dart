import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hyport/core/services/firebase_providers.dart';

/// Self-service password recovery for accounts whose registered phone can
/// receive SMS. Phone Auth proves possession of the phone; the callable
/// function then verifies the email+phone pair before changing the password.
class PhonePasswordRecoveryScreen extends StatefulWidget {
  const PhonePasswordRecoveryScreen({super.key});

  @override
  State<PhonePasswordRecoveryScreen> createState() =>
      _PhonePasswordRecoveryScreenState();
}

class _PhonePasswordRecoveryScreenState
    extends State<PhonePasswordRecoveryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  ConfirmationResult? _webConfirmation;
  String? _mobileVerificationId;
  bool _codeSent = false;
  bool _submitting = false;
  String? _error;

  FirebaseAuth get _auth => FirebaseAuth.instance;

  @override
  void dispose() {
    _email.dispose();
    _phone.dispose();
    _code.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final phone = _phone.text.trim();
      if (kIsWeb) {
        _webConfirmation = await _auth.signInWithPhoneNumber(phone);
        _codeSent = true;
      } else {
        await _auth.verifyPhoneNumber(
          phoneNumber: phone,
          verificationCompleted: (credential) async {
            await _auth.signInWithCredential(credential);
          },
          verificationFailed: (e) => setState(() => _error = e.message),
          codeSent: (verificationId, _) => setState(() {
            _mobileVerificationId = verificationId;
            _codeSent = true;
          }),
          codeAutoRetrievalTimeout: (verificationId) =>
              _mobileVerificationId = verificationId,
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = e.message ?? e.code);
    } catch (e) {
      if (mounted)
        setState(() => _error = 'Could not send the verification code: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _resetPassword() async {
    if (!_formKey.currentState!.validate() || !_codeSent) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      if (kIsWeb) {
        await _webConfirmation!.confirm(_code.text.trim());
      } else {
        final verificationId = _mobileVerificationId;
        if (verificationId == null) throw StateError('Request a new code.');
        final credential = PhoneAuthProvider.credential(
          verificationId: verificationId,
          smsCode: _code.text.trim(),
        );
        await _auth.signInWithCredential(credential);
      }

      await FirebaseFunctions.instance
          .httpsCallable('recoverPasswordByPhone')
          .call({
            'email': _email.text.trim(),
            'phone': _phone.text.trim(),
            'newPassword': _password.text,
          });
      await _auth.signOut();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password reset successfully.')),
        );
        context.go('/login');
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = e.message ?? e.code);
    } on FirebaseFunctionsException catch (e) {
      if (mounted)
        setState(
          () => _error = e.message ?? 'Recovery details could not be verified.',
        );
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not reset password: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recover Password')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.phone_android_rounded, size: 64),
                    const SizedBox(height: 16),
                    Text(
                      'Recover with SMS',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'We will verify your registered phone before changing your password.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Account email',
                      ),
                      validator: (v) => v == null || !v.contains('@')
                          ? 'Enter your registered email'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Registered phone number',
                        hintText: '+233XXXXXXXXX',
                      ),
                      validator: (v) => v == null || v.trim().length < 7
                          ? 'Enter your registered phone number'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    if (!_codeSent)
                      FilledButton(
                        onPressed: _submitting ? null : _sendCode,
                        child: const Text('SEND SMS CODE'),
                      ),
                    if (_codeSent) ...[
                      TextFormField(
                        controller: _code,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'SMS code',
                        ),
                        validator: (v) => v == null || v.trim().length < 4
                            ? 'Enter the SMS code'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _password,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'New password',
                        ),
                        validator: (v) => v == null || v.length < 6
                            ? 'At least 6 characters'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _confirm,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Confirm new password',
                        ),
                        validator: (v) => v != _password.text
                            ? 'Passwords do not match'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _submitting ? null : _resetPassword,
                        child: const Text('RESET PASSWORD'),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => context.go('/login'),
                      child: const Text('Back to Login'),
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

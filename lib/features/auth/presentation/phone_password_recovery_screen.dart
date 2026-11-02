import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Firebase Phone Auth only accepts E.164 numbers (+233…). Accepts the local
/// Ghanaian form (0XXXXXXXXX), the 00-prefixed form, or an already-E.164 number.
String toE164PhoneNumber(String input) {
  final digits = input.replaceAll(RegExp(r'[\s().-]'), '');
  if (digits.startsWith('00')) return '+${digits.substring(2)}';
  if (RegExp(r'^0\d{9}$').hasMatch(digits)) return '+233${digits.substring(1)}';
  return digits;
}

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

  String _friendlyAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-phone-number':
        return 'That phone number is not valid. Use the format 0241234567.';
      case 'too-many-requests':
      case 'quota-exceeded':
        return 'Too many attempts. Please wait a while and try again.';
      case 'invalid-verification-code':
        return 'The SMS code is incorrect. Check it and try again.';
      case 'session-expired':
        return 'The SMS code has expired. Request a new one.';
      default:
        return e.message ?? e.code;
    }
  }

  Future<void> _sendCode() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final phone = toE164PhoneNumber(_phone.text);
      if (kIsWeb) {
        _webConfirmation = await _auth.signInWithPhoneNumber(phone);
        _codeSent = true;
      } else {
        await _auth.verifyPhoneNumber(
          phoneNumber: phone,
          verificationCompleted: (credential) async {
            // Some Android devices verify the SMS automatically. The phone
            // session is then already signed in, so the code step is skipped.
            await _auth.signInWithCredential(credential);
            if (mounted) setState(() => _codeSent = true);
          },
          verificationFailed: (e) =>
              setState(() => _error = _friendlyAuthError(e)),
          codeSent: (verificationId, _) => setState(() {
            _mobileVerificationId = verificationId;
            _codeSent = true;
          }),
          codeAutoRetrievalTimeout: (verificationId) =>
              _mobileVerificationId = verificationId,
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = _friendlyAuthError(e));
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Could not send the verification code: $e');
      }
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
      // Skip the code step if the phone session already exists (automatic
      // verification above, or a confirmed web session).
      if (_auth.currentUser?.phoneNumber == null) {
        if (kIsWeb) {
          final confirmation = _webConfirmation;
          if (confirmation == null) throw StateError('Request a new code.');
          await confirmation.confirm(_code.text.trim());
        } else {
          final verificationId = _mobileVerificationId;
          if (verificationId == null) throw StateError('Request a new code.');
          final credential = PhoneAuthProvider.credential(
            verificationId: verificationId,
            smsCode: _code.text.trim(),
          );
          await _auth.signInWithCredential(credential);
        }
      }

      await FirebaseFunctions.instance
          .httpsCallable('recoverPasswordByPhone')
          .call({
            'email': _email.text.trim(),
            'phone': toE164PhoneNumber(_phone.text),
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
      if (mounted) setState(() => _error = _friendlyAuthError(e));
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        setState(() => _error = e.code == 'permission-denied' ||
                e.code == 'invalid-argument' ||
                e.code == 'unauthenticated'
            ? e.message ?? 'Recovery details could not be verified.'
            : 'Password reset is unavailable right now. Please try again '
                'or contact the Applications Systems Unit.');
      }
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
                        hintText: '0241234567',
                      ),
                      validator: (v) => v == null ||
                              !RegExp(r'^\+\d{8,15}$')
                                  .hasMatch(toE164PhoneNumber(v))
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

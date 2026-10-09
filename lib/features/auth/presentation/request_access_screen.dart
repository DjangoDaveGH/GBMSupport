import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hyport/core/models/enums.dart';
import 'package:hyport/core/services/firebase_providers.dart';
import 'package:hyport/core/theme/app_theme.dart';
import 'package:hyport/features/auth/data/access_request_repository.dart';

/// Submits a request for PFM-Systems to review — does not create an
/// account itself. See DECISIONS.md ("Request Access is a request, not
/// self-signup").
class RequestAccessScreen extends ConsumerStatefulWidget {
  const RequestAccessScreen({super.key});

  @override
  ConsumerState<RequestAccessScreen> createState() =>
      _RequestAccessScreenState();
}

class _RequestAccessScreenState extends ConsumerState<RequestAccessScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _institutionController = TextEditingController();
  final _phoneController = TextEditingController();
  InstitutionType _institutionType = InstitutionType.mda;
  bool _submitting = false;
  bool _done = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _institutionController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await AccessRequestRepository(ref.read(firestoreProvider)).submit(
        fullName: _nameController.text.trim(),
        email: _emailController.text.trim(),
        phone: _phoneController.text.trim(),
        institutionType: _institutionType.wireValue,
        institutionName: _institutionController.text.trim(),
      );
      if (mounted) setState(() => _done = true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not submit request: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: const SizedBox.shrink(),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: _done ? _buildDone(textTheme) : _buildForm(textTheme),
        ),
      ),
    );
  }

  Widget _buildDone(TextTheme textTheme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 24),
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: AppTheme.success.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.check_circle_rounded,
            size: 42,
            color: AppTheme.success,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Request submitted',
          style: textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'PFM-Systems will review your request and reach out with account details.',
          style: textTheme.bodyMedium?.copyWith(color: Colors.black54),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => context.go('/login'),
            child: const Text('Back to Login'),
          ),
        ),
      ],
    );
  }

  Widget _buildForm(TextTheme textTheme) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Image.asset(
                'assets/images/illustration_request_access.png',
                width: 140,
                height: 140,
              ),
            ),
          ),
          Text(
            'Request Access',
            style: textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Fill in the details below to request an account. Our team will review and activate your access.',
            style: textTheme.bodyMedium?.copyWith(color: Colors.black54),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Full Name'),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Enter your full name' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _emailController,
            decoration: const InputDecoration(labelText: 'Work Email'),
            keyboardType: TextInputType.emailAddress,
            validator: (v) =>
                (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<InstitutionType>(
            initialValue: _institutionType,
            decoration: const InputDecoration(labelText: 'Institution Type'),
            items: InstitutionType.values
                .map(
                  (t) => DropdownMenuItem(value: t, child: Text(t.wireValue)),
                )
                .toList(),
            onChanged: (v) => setState(() => _institutionType = v!),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _institutionController,
            decoration: const InputDecoration(labelText: 'Institution / MDA'),
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'Enter your institution'
                : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _phoneController,
            decoration: const InputDecoration(labelText: 'Phone Number'),
            keyboardType: TextInputType.phone,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('SUBMIT REQUEST'),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:hyport/core/models/enums.dart';
import 'package:hyport/features/auth/domain/app_user.dart';

/// Admin-only full user editor (FR-AUTH-06), shared by the mobile and
/// desktop Users screens. Name/email/role/institution/status all live
/// either in Auth custom claims or on the Auth account itself, which only
/// the Admin SDK can touch — so this calls `adminUpdateUser` rather than
/// writing to Firestore directly (see firestore.rules' users/{userId}
/// rule). Only fields the admin actually changes are sent, so an edit that
/// only touches the role doesn't also rewrite name/email server-side.
Future<void> showEditUserDialog(BuildContext context, AppUser user) {
  return showDialog<void>(
    context: context,
    builder: (context) => _EditUserDialog(user: user),
  );
}

class _EditUserDialog extends StatefulWidget {
  final AppUser user;

  const _EditUserDialog({required this.user});

  @override
  State<_EditUserDialog> createState() => _EditUserDialogState();
}

class _EditUserDialogState extends State<_EditUserDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.user.name);
  late final _emailController = TextEditingController(text: widget.user.email);
  late final _phoneController = TextEditingController(text: widget.user.phone);
  late final _institutionIdController = TextEditingController(text: widget.user.institutionId);
  late UserRole _role = widget.user.role;
  late InstitutionType _institutionType = widget.user.institutionType;
  late bool _isActive = widget.user.isActive;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _institutionIdController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final data = <String, dynamic>{'uid': widget.user.id};
      final name = _nameController.text.trim();
      final email = _emailController.text.trim();
      final phone = _phoneController.text.trim();
      final institutionId = _institutionIdController.text.trim();
      if (name != widget.user.name) data['name'] = name;
      if (email != widget.user.email) data['email'] = email;
      if (phone != widget.user.phone) data['phone'] = phone;
      if (institutionId != widget.user.institutionId) data['institutionId'] = institutionId;
      if (_institutionType != widget.user.institutionType) data['institutionType'] = _institutionType.wireValue;
      if (_role != widget.user.role) data['role'] = _role.wireValue;
      if (_isActive != widget.user.isActive) data['isActive'] = _isActive;

      if (data.length == 1) {
        Navigator.of(context).pop();
        return;
      }

      final callable = FirebaseFunctions.instance.httpsCallable('adminUpdateUser');
      await callable.call(data);
      if (mounted) Navigator.of(context).pop();
    } on FirebaseFunctionsException catch (e) {
      if (mounted) setState(() => _error = e.message ?? 'Could not update user (${e.code}).');
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not update user: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit ${widget.user.name}'),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Full name'),
                  enabled: !_submitting,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(labelText: 'Email'),
                  keyboardType: TextInputType.emailAddress,
                  enabled: !_submitting,
                  validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneController,
                  decoration: const InputDecoration(labelText: 'Phone'),
                  keyboardType: TextInputType.phone,
                  enabled: !_submitting,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _institutionIdController,
                  decoration: const InputDecoration(labelText: 'Institution ID'),
                  enabled: !_submitting,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter an institution ID' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<InstitutionType>(
                  initialValue: _institutionType,
                  decoration: const InputDecoration(labelText: 'Institution type'),
                  items: InstitutionType.values
                      .map((t) => DropdownMenuItem(value: t, child: Text(t.wireValue)))
                      .toList(),
                  onChanged: _submitting ? null : (v) => setState(() => _institutionType = v!),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<UserRole>(
                  initialValue: _role,
                  decoration: const InputDecoration(labelText: 'Role'),
                  // technical_lead is retired (behaves like functional_lead
                  // now); only offer it if this user already has it, so the
                  // dropdown's current value still resolves.
                  items: UserRole.values
                      .where((r) => r != UserRole.technicalLead || widget.user.role == UserRole.technicalLead)
                      .map((r) => DropdownMenuItem(value: r, child: Text(r.label)))
                      .toList(),
                  onChanged: _submitting ? null : (v) => setState(() => _role = v!),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active'),
                  subtitle: Text(_isActive ? 'Can sign in' : 'Account disabled — cannot sign in'),
                  value: _isActive,
                  onChanged: _submitting ? null : (v) => setState(() => _isActive = v),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _submitting ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: _submitting ? null : _save,
          child: _submitting
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }
}

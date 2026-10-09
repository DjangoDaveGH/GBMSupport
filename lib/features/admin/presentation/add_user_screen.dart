import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hyport/core/models/enums.dart';
import 'package:hyport/core/models/support_system.dart';
import 'package:hyport/core/theme/app_theme.dart';

/// Admin-provisioned accounts (Section 10: no self-signup). Creating a
/// Firebase Auth user + setting the `role`/`institutionId` custom claims
/// requires the Admin SDK, so this calls the `adminCreateUser` Cloud
/// Function (implemented alongside the Day 3 notification functions) rather
/// than doing it client-side. See DECISIONS.md.
class AddUserScreen extends ConsumerStatefulWidget {
  /// When true, renders just the content with no Scaffold/AppBar of its
  /// own — for embedding inside DesktopShell. See NotificationsScreen's
  /// doc comment for why.
  final bool embedded;
  final String? initialSystem;

  const AddUserScreen({super.key, this.embedded = false, this.initialSystem});

  @override
  ConsumerState<AddUserScreen> createState() => _AddUserScreenState();
}

class _AddUserScreenState extends ConsumerState<AddUserScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _institutionIdController = TextEditingController();
  UserRole _role = UserRole.endUser;
  InstitutionType _institutionType = InstitutionType.mda;
  Set<String> _systems = {'gbms'};
  bool _submitting = false;
  String? _error;
  String? _success;

  @override
  void initState() {
    super.initState();
    if (supportSystemIds.contains(widget.initialSystem)) {
      _systems = {widget.initialSystem!};
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _institutionIdController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
      _success = null;
    });
    try {
      final email = _emailController.text.trim();
      final callable = FirebaseFunctions.instance.httpsCallable(
        'adminCreateUser',
      );
      await callable.call({
        'name': _nameController.text.trim(),
        'email': email,
        'phone': _phoneController.text.trim(),
        'role': _role.wireValue,
        'institutionId': _institutionIdController.text.trim(),
        'institutionType': _institutionType.wireValue,
        'systems': _systems.toList(),
      });
      // The account now exists — clear the form and report success.
      if (!mounted) return;
      _formKey.currentState!.reset();
      _nameController.clear();
      _emailController.clear();
      _phoneController.clear();
      _institutionIdController.clear();
      setState(() {
        _role = UserRole.endUser;
        _systems = supportSystemIds.contains(widget.initialSystem)
            ? {widget.initialSystem!}
            : defaultSystemsForRole(_role);
      });

      if (mounted) {
        setState(
          () => _success =
              'User created. They can recover access using SMS verification with their registered phone.',
        );
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        setState(
          () => _error = e.message ?? 'Could not create user (${e.code}).',
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not create user: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Full name'),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _emailController,
            decoration: const InputDecoration(labelText: 'Email'),
            keyboardType: TextInputType.emailAddress,
            validator: (v) =>
                (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _phoneController,
            decoration: const InputDecoration(labelText: 'Phone'),
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<UserRole>(
            initialValue: _role,
            decoration: const InputDecoration(labelText: 'Role'),
            // technical_lead is retired — it behaves identically to
            // functional_lead now (one Applications Systems Unit), so
            // don't offer it for new accounts.
            items: UserRole.values
                .where((r) => r != UserRole.technicalLead)
                .map((r) => DropdownMenuItem(value: r, child: Text(r.label)))
                .toList(),
            onChanged: (v) => setState(() {
              final previousDefaults = defaultSystemsForRole(_role);
              _role = v!;
              // Apply role-specific defaults only while the user is still
              // using the previous role's defaults. Do not discard an
              // explicit system selection when the role changes.
              if (_systems.length == previousDefaults.length &&
                  _systems.containsAll(previousDefaults)) {
                _systems =
                    supportSystemIds.contains(widget.initialSystem) &&
                        _role != UserRole.supportCoordinator
                    ? {widget.initialSystem!}
                    : defaultSystemsForRole(_role);
              }
            }),
          ),
          const SizedBox(height: 16),
          Text('System access', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Choose which support systems this account belongs to.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final system in supportSystemIds)
                FilterChip(
                  label: Text(supportSystemLabel(system)),
                  selected: _systems.contains(system),
                  selectedColor: AppTheme.navy,
                  checkmarkColor: Colors.white,
                  labelStyle: TextStyle(
                    color: _systems.contains(system)
                        ? Colors.white
                        : AppTheme.navy,
                    fontWeight: FontWeight.w700,
                  ),
                      onSelected: _submitting
                          ? null
                          : (selected) => setState(() {
                              if (selected) {
                                _systems.add(system);
                                if (isTenantScopedSupportRole(_role)) {
                                  if (system == 'gbms') {
                                    _systems.removeAll({'ghaneps', 'gifmis'});
                                  } else {
                                    _systems.remove('gbms');
                                  }
                                }
                              } else if (_systems.length > 1) {
                                _systems.remove(system);
                              }
                            }),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _institutionIdController,
            decoration: const InputDecoration(labelText: 'Institution ID'),
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'Enter an institution ID'
                : null,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<InstitutionType>(
            initialValue: _institutionType,
            decoration: const InputDecoration(labelText: 'Institution type'),
            items: InstitutionType.values
                .map(
                  (t) => DropdownMenuItem(value: t, child: Text(t.wireValue)),
                )
                .toList(),
            onChanged: (v) => setState(() => _institutionType = v!),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            _Banner(
              text: _error!,
              color: Theme.of(context).colorScheme.error,
              icon: Icons.error_outline_rounded,
            ),
          ],
          if (_success != null) ...[
            const SizedBox(height: 16),
            _Banner(
              text: _success!,
              color: StatusColors.resolved,
              icon: Icons.check_circle_outline_rounded,
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _submitting ? null : _submit,
            icon: _submitting
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.person_add_alt_rounded, size: 18),
            label: Text(_submitting ? 'Creating…' : 'Create user'),
          ),
        ],
      ),
    );

    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('Add User')),
      body: body,
    );
  }
}

class _Banner extends StatelessWidget {
  final String text;
  final Color color;
  final IconData icon;

  const _Banner({required this.text, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

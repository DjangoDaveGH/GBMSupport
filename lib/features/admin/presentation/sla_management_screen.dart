import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hyport/core/theme/app_theme.dart';
import 'package:hyport/core/widgets/branded_loader.dart';
import 'package:hyport/features/config/data/sla_providers.dart';
import 'package:hyport/features/config/domain/sla_policy.dart';

/// Real, editable SLA policy — this is the same `config/sla` doc that
/// powers "Overdue" and "SLA Compliance" everywhere else in the app (see
/// SlaCalculator), so a change here has an immediate, real effect rather
/// than being a settings screen for its own sake.
class SlaManagementScreen extends ConsumerStatefulWidget {
  const SlaManagementScreen({super.key});

  @override
  ConsumerState<SlaManagementScreen> createState() => _SlaManagementScreenState();
}

class _SlaManagementScreenState extends ConsumerState<SlaManagementScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _criticalController;
  late final TextEditingController _highController;
  late final TextEditingController _mediumController;
  late final TextEditingController _lowController;
  bool _initialized = false;
  bool _saving = false;

  @override
  void dispose() {
    _criticalController.dispose();
    _highController.dispose();
    _mediumController.dispose();
    _lowController.dispose();
    super.dispose();
  }

  void _initFrom(SlaPolicy policy) {
    _criticalController = TextEditingController(text: '${policy.criticalHours}');
    _highController = TextEditingController(text: '${policy.highHours}');
    _mediumController = TextEditingController(text: '${policy.mediumHours}');
    _lowController = TextEditingController(text: '${policy.lowHours}');
    _initialized = true;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final policy = SlaPolicy(
        criticalHours: int.parse(_criticalController.text.trim()),
        highHours: int.parse(_highController.text.trim()),
        mediumHours: int.parse(_mediumController.text.trim()),
        lowHours: int.parse(_lowController.text.trim()),
      );
      await ref.read(slaRepositoryProvider).update(policy);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('SLA policy saved.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save SLA policy: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _validateHours(String? v) {
    if (v == null || v.trim().isEmpty) return 'Required';
    final n = int.tryParse(v.trim());
    if (n == null || n <= 0) return 'Enter a whole number of hours';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final policyAsync = ref.watch(slaPolicyProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('SLA Management')),
      body: policyAsync.when(
        loading: () => const BrandedLoaderCenter(),
        error: (e, _) => Center(child: Text('Could not load SLA policy: $e')),
        data: (policy) {
          if (!_initialized) _initFrom(policy);
          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Target time to resolve a ticket, by priority. Used to compute "Overdue" and SLA Compliance across the app.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black54),
                ),
                const SizedBox(height: AppSpacing.xl),
                _hoursField('Critical priority', _criticalController),
                const SizedBox(height: AppSpacing.lg),
                _hoursField('High priority', _highController),
                const SizedBox(height: AppSpacing.lg),
                _hoursField('Medium priority', _mediumController),
                const SizedBox(height: AppSpacing.lg),
                _hoursField('Low priority', _lowController),
                const SizedBox(height: AppSpacing.xl),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Save Policy'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _hoursField(String label, TextEditingController controller) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label, suffixText: 'hours'),
      validator: _validateHours,
    );
  }
}

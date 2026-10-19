import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hyport/core/models/enums.dart';
import 'package:hyport/core/models/support_system.dart';
import 'package:hyport/core/theme/app_theme.dart';

/// Keeps the product boundary visible wherever management can change it.
/// The URL is the source of truth so dashboard, queue, and deep links stay in
/// the same workspace after navigation or a browser refresh.
class SupportWorkspaceSwitcher extends StatelessWidget {
  final SupportWorkspace selected;
  final UserRole role;

  const SupportWorkspaceSwitcher({
    super.key,
    required this.selected,
    required this.role,
  });

  @override
  Widget build(BuildContext context) {
    if (role != UserRole.pfmManagement) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth < 620
          ? _buildCompact(context)
          : _buildSegmented(context),
    );
  }

  Widget _buildSegmented(BuildContext context) {
    return SegmentedButton<SupportWorkspace>(
      segments: const [
        ButtonSegment(
          value: SupportWorkspace.gbms,
          label: Text('GBMS'),
          icon: Icon(Icons.account_balance_outlined),
        ),
        ButtonSegment(
          value: SupportWorkspace.external,
          label: Text('GHANEPS + GIFMIS'),
          icon: Icon(Icons.account_tree_outlined),
        ),
        ButtonSegment(
          value: SupportWorkspace.all,
          label: Text('All Systems'),
          icon: Icon(Icons.dashboard_outlined),
        ),
      ],
      selected: {selected},
      showSelectedIcon: false,
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? Colors.white
              : AppTheme.navy;
        }),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? AppTheme.navy
              : Colors.white;
        }),
      ),
      onSelectionChanged: (value) {
        final workspace = value.first;
        final query = workspace.routeSystem == null
            ? ''
            : '?system=${workspace.routeSystem}';
        context.go('/home$query');
      },
    );
  }

  Widget _buildCompact(BuildContext context) {
    return DropdownButtonFormField<SupportWorkspace>(
      initialValue: selected,
      decoration: const InputDecoration(
        labelText: 'Dashboard workspace',
        prefixIcon: Icon(Icons.layers_outlined),
        isDense: true,
      ),
      items: [
        for (final workspace in SupportWorkspace.values)
          DropdownMenuItem(value: workspace, child: Text(workspace.label)),
      ],
      onChanged: (workspace) {
        if (workspace == null) return;
        final query = workspace.routeSystem == null
            ? ''
            : '?system=${workspace.routeSystem}';
        context.go('/home$query');
      },
    );
  }
}

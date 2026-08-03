import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hyport/core/models/enums.dart';
import 'package:hyport/core/theme/app_theme.dart';
import 'package:hyport/features/tickets/data/ticket_providers.dart';

/// Status checkbox groups shown on the mockup's Filters screen (screen 14):
/// Open / In Progress / Pending User / Resolved / Closed. Together they
/// cover every TicketStatus value with no gaps or overlaps, so nothing
/// becomes unreachable through this screen.
class _StatusGroup {
  final String label;
  final Set<TicketStatus> statuses;

  const _StatusGroup(this.label, this.statuses);
}

const _statusGroups = [
  _StatusGroup('Open', {TicketStatus.open}),
  _StatusGroup('In Progress', {TicketStatus.inProgress, TicketStatus.escalated}),
  _StatusGroup('Pending User', {TicketStatus.assigned, TicketStatus.reopened}),
  _StatusGroup('Resolved', {TicketStatus.resolved}),
  _StatusGroup('Closed', {TicketStatus.closed}),
];

class TicketFiltersScreen extends StatefulWidget {
  final TicketFilter initialFilter;

  const TicketFiltersScreen({super.key, required this.initialFilter});

  @override
  State<TicketFiltersScreen> createState() => _TicketFiltersScreenState();
}

class _TicketFiltersScreenState extends State<TicketFiltersScreen> {
  late Set<TicketStatus> _statuses = {...widget.initialFilter.statuses};
  late Set<TicketPriority> _priorities = {...widget.initialFilter.priorities};
  late TicketCategory? _category = widget.initialFilter.category;

  void _toggleGroup(_StatusGroup group, bool checked) {
    setState(() {
      if (checked) {
        _statuses.addAll(group.statuses);
      } else {
        _statuses.removeAll(group.statuses);
      }
    });
  }

  void _togglePriority(TicketPriority priority, bool checked) {
    setState(() {
      if (checked) {
        _priorities.add(priority);
      } else {
        _priorities.remove(priority);
      }
    });
  }

  void _reset() {
    setState(() {
      _statuses = {};
      _priorities = {};
      _category = null;
    });
  }

  void _apply() {
    context.pop(
      TicketFilter(statuses: _statuses, category: _category, priorities: _priorities),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Filters'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  children: [
                    _sectionLabel(context, 'Status'),
                    for (final group in _statusGroups)
                      _FilterCheckboxRow(
                        label: group.label,
                        checked: group.statuses.every(_statuses.contains),
                        onChanged: (v) => _toggleGroup(group, v),
                      ),
                    const SizedBox(height: AppSpacing.xl),
                    _sectionLabel(context, 'Priority'),
                    for (final p in TicketPriority.values)
                      _FilterCheckboxRow(
                        label: p.label,
                        checked: _priorities.contains(p),
                        onChanged: (v) => _togglePriority(p, v),
                      ),
                    const SizedBox(height: AppSpacing.xl),
                    _sectionLabel(context, 'Category'),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<TicketCategory?>(
                      initialValue: _category,
                      decoration: const InputDecoration(hintText: 'All categories'),
                      items: [
                        const DropdownMenuItem<TicketCategory?>(value: null, child: Text('All categories')),
                        ...TicketCategory.values.map((c) => DropdownMenuItem(value: c, child: Text(c.label))),
                      ],
                      onChanged: (v) => setState(() => _category = v),
                    ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(onPressed: _reset, child: const Text('Reset')),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: FilledButton(onPressed: _apply, child: const Text('Apply Filters')),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _sectionLabel(BuildContext context, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    );

class _FilterCheckboxRow extends StatelessWidget {
  final String label;
  final bool checked;
  final ValueChanged<bool> onChanged;

  const _FilterCheckboxRow({required this.label, required this.checked, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      onTap: () => onChanged(!checked),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Checkbox(
              value: checked,
              onChanged: (v) => onChanged(v ?? false),
              activeColor: AppTheme.navy,
            ),
            Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

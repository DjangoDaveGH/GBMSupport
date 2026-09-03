import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hyport/core/auth/auth_providers.dart';
import 'package:hyport/core/models/enums.dart';
import 'package:hyport/core/theme/app_theme.dart';
import 'package:hyport/features/auth/data/institution_providers.dart';
import 'package:hyport/features/tickets/data/ticket_providers.dart';
import 'package:intl/intl.dart';

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

class TicketFiltersScreen extends ConsumerStatefulWidget {
  final TicketFilter initialFilter;

  const TicketFiltersScreen({super.key, required this.initialFilter});

  @override
  ConsumerState<TicketFiltersScreen> createState() => _TicketFiltersScreenState();
}

class _TicketFiltersScreenState extends ConsumerState<TicketFiltersScreen> {
  late Set<TicketStatus> _statuses = {...widget.initialFilter.statuses};
  late Set<TicketPriority> _priorities = {...widget.initialFilter.priorities};
  late TicketCategory? _category = widget.initialFilter.category;
  late String? _institutionId = widget.initialFilter.institutionId;
  late InstitutionType? _institutionType = widget.initialFilter.institutionType;
  late DateTime? _createdAfter = widget.initialFilter.createdAfter;
  late DateTime? _createdBefore = widget.initialFilter.createdBefore;
  late bool _overdueOnly = widget.initialFilter.overdueOnly;

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

  Future<void> _pickDate({required bool isFrom}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: (isFrom ? _createdAfter : _createdBefore) ?? now,
      firstDate: DateTime(2023),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _createdAfter = picked;
        if (_createdBefore != null && _createdBefore!.isBefore(picked)) _createdBefore = picked;
      } else {
        _createdBefore = picked;
        if (_createdAfter != null && _createdAfter!.isAfter(picked)) _createdAfter = picked;
      }
    });
  }

  void _reset() {
    setState(() {
      _statuses = {};
      _priorities = {};
      _category = null;
      _institutionId = null;
      _institutionType = null;
      _createdAfter = null;
      _createdBefore = null;
      _overdueOnly = false;
    });
  }

  void _apply() {
    context.pop(
      TicketFilter(
        statuses: _statuses,
        category: _category,
        priorities: _priorities,
        institutionId: _institutionId,
        institutionType: _institutionType,
        createdAfter: _createdAfter,
        createdBefore: _createdBefore,
        overdueOnly: _overdueOnly,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Institution / date / SLA filters are triage tools — only the
    // support-side queue ("Ticket Queue") needs them; on a requester's
    // "My Tickets" list they'd add only noise.
    final isSupportSide = ref.watch(currentAppUserProvider).valueOrNull?.role.isSupportSide ?? false;
    final institutions = [...?ref.watch(institutionListProvider).valueOrNull]..sort((a, b) => a.name.compareTo(b.name));

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
                    if (isSupportSide) ...[
                      const SizedBox(height: AppSpacing.xl),
                      _sectionLabel(context, 'Institution'),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final option in const [
                            ('All types', null),
                            ('MDA', InstitutionType.mda),
                            ('MMDA', InstitutionType.mmda),
                          ])
                            ChoiceChip(
                              label: Text(option.$1),
                              selected: _institutionType == option.$2,
                              showCheckmark: false,
                              selectedColor: AppTheme.navy,
                              labelStyle: TextStyle(
                                color: _institutionType == option.$2 ? Colors.white : AppTheme.ink,
                                fontWeight: FontWeight.w600,
                              ),
                              backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
                              onSelected: (_) => setState(() => _institutionType = option.$2),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String?>(
                        initialValue: institutions.any((i) => i.id == _institutionId) ? _institutionId : null,
                        isExpanded: true,
                        decoration: const InputDecoration(hintText: 'All institutions'),
                        items: [
                          const DropdownMenuItem<String?>(value: null, child: Text('All institutions')),
                          ...institutions.map((i) => DropdownMenuItem(value: i.id, child: Text(i.name, overflow: TextOverflow.ellipsis))),
                        ],
                        onChanged: (v) => setState(() => _institutionId = v),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      _sectionLabel(context, 'Created date'),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: _DateField(
                              label: 'From',
                              value: _createdAfter,
                              onPick: () => _pickDate(isFrom: true),
                              onClear: () => setState(() => _createdAfter = null),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _DateField(
                              label: 'To',
                              value: _createdBefore,
                              onPick: () => _pickDate(isFrom: false),
                              onClear: () => setState(() => _createdBefore = null),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      _sectionLabel(context, 'SLA'),
                      _FilterCheckboxRow(
                        label: 'Overdue only',
                        checked: _overdueOnly,
                        onChanged: (v) => setState(() => _overdueOnly = v),
                      ),
                    ],
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

class _DateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final VoidCallback onPick;
  final VoidCallback onClear;

  const _DateField({required this.label, required this.value, required this.onPick, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      onTap: onPick,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          suffixIcon: value == null
              ? const Icon(Icons.calendar_today_rounded, size: 16)
              : IconButton(icon: const Icon(Icons.close_rounded, size: 16), onPressed: onClear),
        ),
        child: Text(
          value == null ? 'Any' : DateFormat.yMMMd().format(value!),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}

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

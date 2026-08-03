import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hyport/core/auth/auth_providers.dart';
import 'package:hyport/core/models/enums.dart';
import 'package:hyport/core/offline/connectivity_provider.dart';
import 'package:hyport/core/services/firebase_providers.dart';
import 'package:hyport/core/theme/app_theme.dart';
import 'package:hyport/features/tickets/data/draft_ticket.dart';
import 'package:hyport/features/tickets/data/ticket_providers.dart';
import 'package:hyport/features/tickets/domain/ticket.dart';
import 'package:hyport/features/tickets/presentation/ticket_list_screen.dart'
    show categoryIcon;
import 'package:uuid/uuid.dart';

const _stepHeadlines = [
  'Select Issue Category',
  'Describe Your Issue',
  'Impact & Priority',
  'Add Attachments (Optional)',
  'Review & Submit',
];

/// The mockup's Step 2 is a single description box — no separate Title
/// field. `Ticket.title` still exists (ticket-list rows, notifications, etc.
/// all key off it), so it's derived from the description instead of typed:
/// the first sentence/line, trimmed to a scannable length.
String deriveTicketTitle(String description) {
  final trimmed = description.trim();
  if (trimmed.isEmpty) return 'Untitled ticket';
  final firstLine = trimmed.split(RegExp(r'[\n\r]')).first.trim();
  final match = RegExp(r'^(.*?[.!?])(\s|$)').firstMatch(firstLine);
  final candidate = (match?.group(1) ?? firstLine).trim();
  if (candidate.length <= 70) return candidate;
  return '${candidate.substring(0, 70).trim()}…';
}

String _formatFileSize(int? bytes) {
  if (bytes == null) return '';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class NewTicketScreen extends ConsumerStatefulWidget {
  const NewTicketScreen({super.key});

  @override
  ConsumerState<NewTicketScreen> createState() => _NewTicketScreenState();
}

class _NewTicketScreenState extends ConsumerState<NewTicketScreen> {
  final _descriptionFormKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();

  int _step = 0;
  TicketCategory? _category;
  TicketImpact? _impact;
  TicketPriority? _priority;
  bool _affectsMultipleUsers = false;
  final List<PlatformFile> _attachments = [];
  bool _submitting = false;
  Ticket? _submittedTicket;

  @override
  void initState() {
    super.initState();
    // The Continue button's enabled state depends on the live text in this
    // controller, so it needs a rebuild on every keystroke, not just when
    // the user taps something that already calls setState.
    _descriptionController.addListener(_onTextChanged);
  }

  void _onTextChanged() => setState(() {});

  @override
  void dispose() {
    _descriptionController.removeListener(_onTextChanged);
    _descriptionController.dispose();
    super.dispose();
  }

  bool get _canAdvance => switch (_step) {
    0 => _category != null,
    1 => _descriptionController.text.trim().isNotEmpty,
    2 => _impact != null && _priority != null,
    _ => true,
  };

  void _next() {
    if (_step == 1 &&
        !(_descriptionFormKey.currentState?.validate() ?? false)) {
      return;
    }
    if (_step < _stepHeadlines.length - 1) {
      setState(() => _step++);
    } else {
      _submit();
    }
  }

  void _back() {
    if (_step > 0) setState(() => _step--);
  }

  void _selectCategory(TicketCategory c) {
    setState(() {
      _category = c;
      _step = 1;
    });
  }

  Future<void> _pickAttachment() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
    );
    if (result != null) {
      setState(() => _attachments.addAll(result.files));
    }
  }

  Future<void> _submit() async {
    final appUser = ref.read(currentAppUserProvider).valueOrNull;
    if (appUser == null || _category == null || _priority == null || _impact == null) {
      return;
    }

    setState(() => _submitting = true);
    final isOnline = ref.read(isOnlineProvider).valueOrNull ?? true;
    var attachmentsFailed = false;
    Ticket? createdTicket;
    final description = _descriptionController.text.trim();
    final title = deriveTicketTitle(description);

    try {
      if (isOnline) {
        var urls = <String>[];
        if (_attachments.isNotEmpty) {
          try {
            urls = await _uploadAttachments(appUser.id);
          } catch (_) {
            // Storage may not be provisioned yet (e.g. billing not set up) —
            // don't let an attachment failure block ticket submission itself.
            attachmentsFailed = true;
          }
        }
        createdTicket = await ref
            .read(ticketRepositoryProvider)
            .createTicket(
              createdBy: appUser.id,
              institutionId: appUser.institutionId,
              category: _category!,
              subCategory: '',
              title: title,
              description: description,
              attachmentUrls: urls,
              priority: _priority!,
              impact: _impact!,
              affectsMultipleUsers: _affectsMultipleUsers,
            );
      } else {
        final draft = DraftTicket(
          localId: const Uuid().v4(),
          createdBy: appUser.id,
          institutionId: appUser.institutionId,
          category: _category!,
          subCategory: '',
          title: title,
          description: description,
          localAttachmentPaths: _attachments
              .map((f) => f.path ?? f.name)
              .toList(),
          priority: _priority!,
          impact: _impact!,
          affectsMultipleUsers: _affectsMultipleUsers,
          createdAt: DateTime.now(),
        );
        await ref.read(draftTicketRepositoryProvider).save(draft);
      }
      if (mounted) {
        final message = !isOnline
            ? 'You\'re offline — ticket saved and will submit automatically once you\'re back online.'
            : attachmentsFailed
            ? 'Ticket submitted, but attachments could not be uploaded (attachment storage isn\'t available yet). Add them later via a comment.'
            : 'Ticket submitted.';
        if (createdTicket != null) {
          setState(() => _submittedTicket = createdTicket);
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message)));
          context.pop();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not submit ticket: $e')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<List<String>> _uploadAttachments(String userId) async {
    if (_attachments.isEmpty) return [];
    final storage = ref.read(firebaseStorageProvider);
    final urls = <String>[];
    for (final file in _attachments) {
      if (file.bytes == null) continue;
      final storageRef = storage.ref(
        'attachments/$userId/${DateTime.now().millisecondsSinceEpoch}_${file.name}',
      );
      final snapshot = await storageRef.putData(file.bytes!);
      urls.add(await snapshot.ref.getDownloadURL());
    }
    return urls;
  }

  @override
  Widget build(BuildContext context) {
    final isOnline = ref.watch(isOnlineProvider).valueOrNull ?? true;

    if (_submittedTicket != null) {
      return _TicketSubmittedScreen(ticket: _submittedTicket!);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create New Ticket'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      // Centered/width-capped rather than stretched full-width — this wizard
      // isn't wrapped in DesktopShell (back-office roles don't create
      // tickets per Section 3), but it's still reachable on a wide browser
      // by requester-side roles, who always get the mobile-style UI
      // regardless of viewport width. Without this it looked like a phone
      // screen awkwardly pinned to the left of a big blank page.
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            children: [
              _StepStepper(step: _step, total: _stepHeadlines.length),
              if (!isOnline)
                Container(
                  padding: const EdgeInsets.all(14),
                  margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  decoration: BoxDecoration(
                    color: AppTheme.gold.withValues(alpha: 0.08),
                    border: Border.all(
                      color: AppTheme.gold.withValues(alpha: 0.35),
                    ),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.cloud_off_rounded, color: AppTheme.gold),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'You\'re offline. This ticket will be saved locally and submitted automatically once you\'re back online.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: KeyedSubtree(
                    key: ValueKey(_step),
                    child: switch (_step) {
                      0 => _CategoryStep(
                        selectedCategory: _category,
                        onCategorySelected: _selectCategory,
                      ),
                      1 => _DescriptionStep(
                        formKey: _descriptionFormKey,
                        controller: _descriptionController,
                      ),
                      2 => _ImpactPriorityStep(
                        impact: _impact,
                        priority: _priority,
                        affectsMultipleUsers: _affectsMultipleUsers,
                        onImpactChanged: (v) => setState(() => _impact = v),
                        onPriorityChanged: (v) => setState(() => _priority = v),
                        onAffectsChanged: (v) =>
                            setState(() => _affectsMultipleUsers = v),
                      ),
                      3 => _AttachmentsStep(
                        attachments: _attachments,
                        isOnline: isOnline,
                        onPick: _pickAttachment,
                        onRemove: (f) => setState(() => _attachments.remove(f)),
                      ),
                      _ => _ReviewStep(
                        category: _category!,
                        impact: _impact!,
                        priority: _priority!,
                        affectsMultipleUsers: _affectsMultipleUsers,
                        description: _descriptionController.text.trim(),
                        attachmentCount: _attachments.length,
                      ),
                    },
                  ),
                ),
              ),
              _WizardNav(
                step: _step,
                totalSteps: _stepHeadlines.length,
                canAdvance: _canAdvance,
                submitting: _submitting,
                onBack: _back,
                onNext: _next,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TicketSubmittedScreen extends StatelessWidget {
  final Ticket ticket;

  const _TicketSubmittedScreen({required this.ticket});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 104,
                height: 104,
                decoration: const BoxDecoration(
                  color: Color(0xFF1FA774),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: Colors.white,
                  size: 64,
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'Ticket Created Successfully!',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'Your request has been submitted and our team will respond shortly.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ticket ID',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      ticket.ticketReference,
                      style: Theme.of(
                        context,
                      ).textTheme.titleMedium?.copyWith(color: AppTheme.navy),
                    ),
                    const Divider(height: 24),
                    Text(
                      'Priority',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      ticket.priority.label,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: StatusColors.high,
                      ),
                    ),
                    const Divider(height: 24),
                    Text(
                      'Assigned Queue',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      'Technical Support Team',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ],
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => context.push('/tickets/${ticket.id}'),
                  child: const Text('VIEW MY TICKET'),
                ),
              ),
              TextButton(
                onPressed: () => context.go('/tickets'),
                child: const Text('Create Another Ticket'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Numbered-circle stepper with connecting lines, matching the mockup's
/// header (1-2-3-4-5, current/completed steps filled navy, upcoming steps
/// outlined gray), plus a "Step X of 5" label above each step's headline.
class _StepStepper extends StatelessWidget {
  final int step;
  final int total;

  const _StepStepper({required this.step, required this.total});

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outlineVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: List.generate(total * 2 - 1, (i) {
              if (i.isOdd) {
                final leftDone = (i - 1) ~/ 2 < step;
                return Expanded(
                  child: Container(
                    height: 2,
                    color: leftDone ? AppTheme.navy : outline,
                  ),
                );
              }
              final index = i ~/ 2;
              final done = index <= step;
              return Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done ? AppTheme.navy : Colors.white,
                  border: Border.all(color: done ? AppTheme.navy : outline, width: 1.4),
                ),
                child: Text(
                  '${index + 1}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: done ? Colors.white : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 10),
          Text(
            'Step ${step + 1} of $total',
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: Colors.black45),
          ),
          const SizedBox(height: 4),
          Text(
            _stepHeadlines[step],
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ],
      ),
    );
  }
}

class _WizardNav extends StatelessWidget {
  final int step;
  final int totalSteps;
  final bool canAdvance;
  final bool submitting;
  final VoidCallback onBack;
  final VoidCallback onNext;

  const _WizardNav({
    required this.step,
    required this.totalSteps,
    required this.canAdvance,
    required this.submitting,
    required this.onBack,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final isLast = step == totalSteps - 1;

    // Review & Submit (mockup screen 12) stacks full-width buttons —
    // Submit on top, Back beneath — unlike every other step, which keeps a
    // side-by-side Back/Next row.
    if (isLast) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: (canAdvance && !submitting) ? onNext : null,
                  icon: submitting
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_rounded, size: 18),
                  label: Text(submitting ? 'Submitting…' : 'Submit Ticket'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: submitting ? null : onBack,
                  child: const Text('Back'),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Row(
          children: [
            if (step > 0)
              Expanded(
                child: OutlinedButton(
                  onPressed: submitting ? null : onBack,
                  child: const Text('Back'),
                ),
              ),
            if (step > 0) const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: (canAdvance && !submitting) ? onNext : null,
                icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                label: const Text('Next'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Step 1 — flat, chevron-navigable category list (mockup screen 8).
/// Selecting a category advances straight to Step 2, same as tapping a
/// chevron row implies "go" rather than "mark selected, then press Next".
class _CategoryStep extends StatelessWidget {
  final TicketCategory? selectedCategory;
  final ValueChanged<TicketCategory> onCategorySelected;

  const _CategoryStep({
    required this.selectedCategory,
    required this.onCategorySelected,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: TicketCategory.values.length,
      separatorBuilder: (context, i) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final c = TicketCategory.values[i];
        final selected = c == selectedCategory;
        return Material(
          color: selected ? AppTheme.accentBlue.withValues(alpha: 0.06) : Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: () => onCategorySelected(c),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: selected
                      ? AppTheme.accentBlue
                      : Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppTheme.accentBlue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Icon(categoryIcon(c), size: 18, color: AppTheme.accentBlue),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(c.label, style: Theme.of(context).textTheme.titleSmall),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Step 2 — single description box (mockup screen 9), no separate Title.
class _DescriptionStep extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController controller;

  const _DescriptionStep({required this.formKey, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        children: [
          Text(
            'Provide a clear and concise description of the issue.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.black54),
          ),
          const SizedBox(height: AppSpacing.lg),
          TextFormField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: 'Type your issue description here...',
              alignLabelWithHint: true,
            ),
            maxLines: 10,
            minLines: 8,
            maxLength: 1000,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Describe the issue' : null,
          ),
        ],
      ),
    );
  }
}

/// Step 3 — Impact + Priority dropdowns, and who the issue affects (mockup
/// screen 10).
class _ImpactPriorityStep extends StatelessWidget {
  final TicketImpact? impact;
  final TicketPriority? priority;
  final bool affectsMultipleUsers;
  final ValueChanged<TicketImpact?> onImpactChanged;
  final ValueChanged<TicketPriority?> onPriorityChanged;
  final ValueChanged<bool> onAffectsChanged;

  const _ImpactPriorityStep({
    required this.impact,
    required this.priority,
    required this.affectsMultipleUsers,
    required this.onImpactChanged,
    required this.onPriorityChanged,
    required this.onAffectsChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        _stepLabel(context, 'Impact'),
        DropdownButtonFormField<TicketImpact>(
          initialValue: impact,
          decoration: const InputDecoration(hintText: 'Select impact level'),
          items: TicketImpact.values
              .map((i) => DropdownMenuItem(value: i, child: Text(i.label)))
              .toList(),
          onChanged: onImpactChanged,
        ),
        const SizedBox(height: AppSpacing.lg),
        _stepLabel(context, 'Priority'),
        DropdownButtonFormField<TicketPriority>(
          initialValue: priority,
          decoration: const InputDecoration(hintText: 'Select priority level'),
          items: TicketPriority.values
              .map((p) => DropdownMenuItem(value: p, child: Text(p.label)))
              .toList(),
          onChanged: onPriorityChanged,
        ),
        const SizedBox(height: AppSpacing.lg),
        _stepLabel(context, 'Affects'),
        Row(
          children: [
            Expanded(
              child: _AffectsOption(
                label: 'Only Me',
                selected: !affectsMultipleUsers,
                onTap: () => onAffectsChanged(false),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _AffectsOption(
                label: 'Multiple Users',
                selected: affectsMultipleUsers,
                onTap: () => onAffectsChanged(true),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AffectsOption extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _AffectsOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppTheme.accentBlue.withValues(alpha: 0.08) : Colors.white,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: selected
                  ? AppTheme.accentBlue
                  : Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                size: 18,
                color: selected
                    ? AppTheme.accentBlue
                    : Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _stepLabel(BuildContext context, String text) => Padding(
  padding: const EdgeInsets.only(bottom: 6),
  child: Text(
    text,
    style: Theme.of(
      context,
    ).textTheme.labelMedium?.copyWith(color: Colors.black54),
  ),
);

/// Step 4 — dropzone-style attachment picker (mockup screen 11).
class _AttachmentsStep extends StatelessWidget {
  final List<PlatformFile> attachments;
  final bool isOnline;
  final VoidCallback onPick;
  final ValueChanged<PlatformFile> onRemove;

  const _AttachmentsStep({
    required this.attachments,
    required this.isOnline,
    required this.onPick,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outline;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        Text(
          'Upload any files, screenshots or documents related to the issue.',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: Colors.black54),
        ),
        const SizedBox(height: AppSpacing.lg),
        Material(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            onTap: isOnline ? onPick : null,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(
                  color: outline,
                  width: 1.4,
                  style: BorderStyle.solid,
                ),
              ),
              child: Column(
                children: [
                  Icon(Icons.cloud_upload_outlined, size: 34, color: AppTheme.accentBlue),
                  const SizedBox(height: 10),
                  Text(
                    isOnline
                        ? 'Tap to upload or drag and drop'
                        : 'Attachments unavailable offline',
                    style: Theme.of(context).textTheme.titleSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'PDF, PNG, JPG up to 10MB each',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (attachments.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          ...attachments.map(
            (f) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.insert_drive_file_outlined, size: 20, color: AppTheme.accentBlue),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      f.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(_formatFileSize(f.size), style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: () => onRemove(f),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Step 5 — review card matching the mockup's Category/Impact/Priority/
/// Affects rows, plus the description text (kept deliberately — see
/// DECISIONS.md — dropping the actual issue text before final submit would
/// be a real regression, not just a style simplification).
class _ReviewStep extends StatelessWidget {
  final TicketCategory category;
  final TicketImpact impact;
  final TicketPriority priority;
  final bool affectsMultipleUsers;
  final String description;
  final int attachmentCount;

  const _ReviewStep({
    required this.category,
    required this.impact,
    required this.priority,
    required this.affectsMultipleUsers,
    required this.description,
    required this.attachmentCount,
  });

  Color get _priorityColor => switch (priority) {
    TicketPriority.critical => StatusColors.critical,
    TicketPriority.high => StatusColors.high,
    TicketPriority.medium => StatusColors.medium,
    TicketPriority.low => StatusColors.low,
  };

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        Text(
          'Please review your ticket details before submitting.',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: Colors.black54),
        ),
        const SizedBox(height: AppSpacing.md),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ReviewRow(label: 'Category', value: category.label),
              _ReviewRow(label: 'Impact', value: impact.label),
              _ReviewRow(
                label: 'Priority',
                valueWidget: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _priorityColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    priority.label,
                    style: Theme.of(
                      context,
                    ).textTheme.labelMedium?.copyWith(color: _priorityColor),
                  ),
                ),
              ),
              _ReviewRow(
                label: 'Affects',
                value: affectsMultipleUsers ? 'Multiple Users' : 'Only Me',
                showDivider: false,
              ),
              const Divider(height: 28),
              Text('Description', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              Text(
                description,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Colors.black87),
              ),
              if (attachmentCount > 0) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(
                      Icons.attach_file_rounded,
                      size: 16,
                      color: Colors.black45,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '$attachmentCount attachment${attachmentCount == 1 ? '' : 's'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ReviewRow extends StatelessWidget {
  final String label;
  final String? value;
  final Widget? valueWidget;
  final bool showDivider;

  const _ReviewRow({
    required this.label,
    this.value,
    this.valueWidget,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: showDivider ? 12 : 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          const Spacer(),
          valueWidget ??
              Text(
                value ?? '',
                style: Theme.of(context).textTheme.titleSmall,
              ),
        ],
      ),
    );
  }
}

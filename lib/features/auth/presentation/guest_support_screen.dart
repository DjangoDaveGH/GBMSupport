import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

const _issueCategories = <String>[
  'Login & Account Access',
  'Registration & Onboarding',
  'Tender Creation & Publishing',
  'Bid Submission',
  'Evaluation & Award',
  'Payments & Fees',
  'Notifications & Emails',
  'User Roles & Permissions',
  'General Support',
];

IconData _categoryIcon(String category) => switch (category) {
  'Login & Account Access' => Icons.person_rounded,
  'Registration & Onboarding' => Icons.account_balance_rounded,
  'Tender Creation & Publishing' => Icons.gavel_rounded,
  'Bid Submission' => Icons.task_alt_rounded,
  'Evaluation & Award' => Icons.assignment_turned_in_rounded,
  'Payments & Fees' => Icons.payments_rounded,
  'Notifications & Emails' => Icons.notifications_active_rounded,
  'User Roles & Permissions' => Icons.admin_panel_settings_rounded,
  _ => Icons.lock_outline_rounded,
};

class GuestSupportScreen extends StatefulWidget {
  final String product;
  final String? ticketReference;
  const GuestSupportScreen({
    super.key,
    required this.product,
    this.ticketReference,
  });
  @override
  State<GuestSupportScreen> createState() => _GuestSupportScreenState();
}

class _GuestSupportScreenState extends State<GuestSupportScreen> {
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _reference = TextEditingController();
  final _description = TextEditingController();
  final _categorySearch = TextEditingController();
  final List<PlatformFile> _attachments = [];
  // Public users submit as guests. Government-institution users sign in to
  // their requester accounts and use the authenticated My Tickets workflow.
  static const _requesterType = 'public';
  String _category = _issueCategories.first;
  String _categoryQuery = '';
  String _mode = 'contact';
  bool _busy = false;
  String? _message;
  Map<String, dynamic>? _status;
  int _detailTab = 0;

  String get _product =>
      widget.product.toLowerCase() == 'gifmis' ? 'gifmis' : 'ghaneps';
  String get _productName => _product.toUpperCase();

  @override
  void initState() {
    super.initState();
    final reference = widget.ticketReference;
    if (reference != null && reference.isNotEmpty) {
      _reference.text = reference;
      _mode = 'lookup';
    }
  }

  void _goBack() {
    if (_mode == 'contact' || _mode == 'faq') {
      context.go('/support/$_product');
      return;
    }
    setState(() {
      _mode = switch (_mode) {
        'compose' => 'contact',
        'describe' => 'compose',
        'result' => 'lookup',
        _ => 'contact',
      };
      _status = null;
      _message = null;
    });
  }

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> data,
  ) async {
    final result = await FirebaseFunctions.instance
        .httpsCallable(name)
        .call(data);
    return Map<String, dynamic>.from(result.data as Map);
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(
          () => _message =
              'We could not complete that request. Please check your details and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _phone.dispose();
    _reference.dispose();
    _description.dispose();
    _categorySearch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(switch (_mode) {
          'compose' || 'describe' => 'Create New Ticket',
          'lookup' => '',
          'result' => 'Ticket Details',
          'success' => '',
          _ => '$_productName Support',
        }),
        leading: IconButton(
          tooltip: 'Back',
          onPressed: _goBack,
          icon: const Icon(Icons.chevron_left_rounded, size: 32),
        ),
      ),
      body: SafeArea(
        child: _mode == 'compose' || _mode == 'describe'
            ? _wizardScreen(context)
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      if (_product == 'ghaneps' && _mode == 'contact') ...[
                        Center(
                          child: Image.asset(
                            'assets/images/ghaneps_logo.png',
                            width: 172,
                            height: 48,
                            fit: BoxFit.contain,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'MINISTRY FOR FINANCE\nREPUBLIC OF GHANA',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF10345F),
                            fontWeight: FontWeight.w600,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (_mode == 'lookup') ...[
                        const SizedBox(height: 12),
                        Center(
                          child: Image.asset(
                            'assets/images/mof_logo.png',
                            width: 132,
                            height: 132,
                            fit: BoxFit.contain,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (_mode == 'faq') ..._faq(),
                      if (_mode == 'contact') ..._contact(),
                      if (_mode == 'success') ..._success(),
                      if (_mode == 'lookup') ..._lookup(),
                      if (_mode == 'result') ..._result(),
                      if (_message != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Text(
                            _message!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      if (_busy)
                        const Padding(
                          padding: EdgeInsets.all(20),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  List<Widget> _contact() => [
    const SizedBox(height: 42),
    Text(
      'Welcome 👋',
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
        color: const Color(0xFF10345F),
        fontWeight: FontWeight.w800,
      ),
    ),
    const SizedBox(height: 10),
    const Text(
      'Please enter your email and phone number to continue',
      textAlign: TextAlign.center,
    ),
    const SizedBox(height: 48),
    TextField(
      controller: _email,
      keyboardType: TextInputType.emailAddress,
      decoration: const InputDecoration(
        labelText: 'Email Address',
        hintText: 'youremail@mda.gov.gh',
      ),
    ),
    const SizedBox(height: 12),
    TextField(
      controller: _phone,
      keyboardType: TextInputType.phone,
      decoration: const InputDecoration(
        labelText: 'Phone Number',
        hintText: '+233 12 345 6789',
      ),
    ),
    const SizedBox(height: 56),
    FilledButton(
      onPressed: () {
        if (!_email.text.contains('@') || _phone.text.trim().length < 7) {
          setState(
            () => _message = 'Enter a valid email address and phone number.',
          );
          return;
        }
        setState(() {
          _message = null;
          _mode = 'compose';
        });
      },
      child: const Text('Book a Ticket'),
    ),
    const SizedBox(height: 12),
    FilledButton(
      onPressed: () => setState(() {
        _message = null;
        _mode = 'lookup';
      }),
      child: const Text('Check Status'),
    ),
    if (_message == null)
      TextButton(
        onPressed: () => setState(() => _mode = 'faq'),
        child: const Text('View FAQs'),
      ),
  ];

  Widget _wizardScreen(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
            child: _GuestWizardProgress(step: _mode == 'compose' ? 0 : 1),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
              children: _mode == 'compose' ? _compose() : _describe(),
            ),
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                _message!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
              child: _mode == 'compose'
                  ? SizedBox(
                      width: double.infinity,
                      height: 62,
                      child: FilledButton(
                        onPressed: () => setState(() => _mode = 'describe'),
                        child: const Text('Next'),
                      ),
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => setState(() => _mode = 'compose'),
                            child: const Text('Back'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: FilledButton(
                            onPressed: _busy ? null : () => _run(_submitTicket),
                            child: _busy
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('Submit Ticket'),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    ),
  );

  List<Widget> _compose() => [
    Text(
      'Select Issue Category',
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
        color: const Color(0xFF2867B2),
        fontWeight: FontWeight.w700,
      ),
    ),
    const SizedBox(height: 16),
    TextField(
      controller: _categorySearch,
      onChanged: (value) => setState(() => _categoryQuery = value),
      decoration: const InputDecoration(
        prefixIcon: Icon(Icons.search_rounded),
        hintText: 'Search Category',
      ),
    ),
    const SizedBox(height: 8),
    for (final category in _issueCategories.where(
      (item) => item.toLowerCase().contains(_categoryQuery.toLowerCase()),
    ))
      InkWell(
        onTap: () => setState(() => _category = category),
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFF2867D8),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _categoryIcon(category),
                  color: Colors.white,
                  size: 21,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  category,
                  style: const TextStyle(
                    color: Color(0xFF10345F),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF10345F),
                size: 30,
              ),
            ],
          ),
        ),
      ),
  ];

  List<Widget> _describe() => [
    const Text('Provide a clear and concise description of the issue.'),
    const SizedBox(height: 16),
    TextField(
      controller: _description,
      minLines: 4,
      maxLines: 8,
      maxLength: 4000,
      decoration: const InputDecoration(labelText: 'Describe the issue'),
    ),
    const SizedBox(height: 16),
    const Text('Add Attachments (Optional)'),
    const SizedBox(height: 8),
    OutlinedButton.icon(
      onPressed: _attachments.length >= 3 ? null : _pickAttachments,
      icon: const Icon(Icons.attach_file_rounded),
      label: Text(
        _attachments.isEmpty
            ? 'Add screenshot or PDF (up to 3 files)'
            : 'Add another file (${_attachments.length}/3)',
      ),
    ),
    for (final file in _attachments)
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.insert_drive_file_outlined),
        title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(_formatSize(file.size)),
        trailing: IconButton(
          tooltip: 'Remove ${file.name}',
          onPressed: () => setState(() => _attachments.remove(file)),
          icon: const Icon(Icons.close_rounded),
        ),
      ),
  ];

  Future<void> _pickAttachments() async {
    final picked = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf'],
    );
    if (picked == null || !mounted) return;
    final selection = [..._attachments, ...picked.files];
    final totalSize = selection.fold<int>(0, (sum, file) => sum + file.size);
    if (selection.length > 3 ||
        totalSize > 5 * 1024 * 1024 ||
        selection.any((file) => file.bytes == null)) {
      setState(
        () => _message = 'Choose up to 3 JPG, PNG, or PDF files, 5 MB total.',
      );
      return;
    }
    setState(() {
      _attachments
        ..clear()
        ..addAll(selection);
      _message = null;
    });
  }

  String _formatSize(int bytes) => bytes < 1024 * 1024
      ? '${(bytes / 1024).ceil()} KB'
      : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  Future<void> _loadTicketStatus() async {
    final result = await _call('lookupGuestTicketStatus', {
      'ticketReference': _reference.text.trim(),
    });
    if (!mounted) return;
    if (result['found'] != true) {
      setState(() {
        _message =
            'We could not find that ticket. Check the ticket number and try again.';
      });
      return;
    }
    setState(() {
      _status = result;
      _detailTab = 0;
      _message = null;
      _mode = 'result';
    });
  }

  Future<void> _submitTicket() async {
    final description = _description.text.trim();
    if (description.length < 10) {
      setState(
        () => _message = 'Please describe the issue in at least 10 characters.',
      );
      return;
    }
    final firstLine = description.split(RegExp(r'[\r\n]')).first.trim();
    final sentence =
        RegExp(r'^(.*?[.!?])(?:\s|$)').firstMatch(firstLine)?.group(1) ??
        firstLine;
    final title = sentence.length > 120 ? sentence.substring(0, 120) : sentence;
    final result = await _call('submitGuestTicket', {
      'system': _product,
      'requesterType': _requesterType,
      'email': _email.text.trim(),
      'phone': _phone.text.trim(),
      'category': _category,
      'title': title,
      'description': description,
      'attachments': _attachments
          .map(
            (file) => {
              'name': file.name,
              'contentType': file.extension?.toLowerCase() == 'pdf'
                  ? 'application/pdf'
                  : file.extension?.toLowerCase() == 'png'
                  ? 'image/png'
                  : 'image/jpeg',
              'data': base64Encode(file.bytes!),
            },
          )
          .toList(),
    });
    if (!mounted) return;
    setState(() {
      _reference.text = result['ticketReference'] as String? ?? '';
      _mode = 'success';
    });
  }

  List<Widget> _success() => [
    const SizedBox(height: 36),
    const CircleAvatar(
      radius: 42,
      backgroundColor: Color(0xFF1FA774),
      child: Icon(Icons.check_rounded, color: Colors.white, size: 52),
    ),
    const SizedBox(height: 24),
    Text(
      'Ticket Created Successfully!',
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.headlineSmall,
    ),
    const SizedBox(height: 8),
    const Text(
      'Your request has been submitted and our team will respond shortly.',
      textAlign: TextAlign.center,
    ),
    const SizedBox(height: 24),
    FilledButton(
      onPressed: _busy ? null : () => _run(_loadTicketStatus),
      child: const Text('View My Ticket'),
    ),
  ];

  List<Widget> _lookup() => [
    const SizedBox(height: 42),
    Text(
      'Check Status',
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
        color: const Color(0xFF10345F),
        fontWeight: FontWeight.w800,
      ),
    ),
    const SizedBox(height: 8),
    const Text(
      'Please input your Ticket Number to check the progress of your Ticket',
      textAlign: TextAlign.center,
    ),
    const SizedBox(height: 20),
    TextField(
      controller: _reference,
      textCapitalization: TextCapitalization.characters,
      decoration: const InputDecoration(hintText: 'Input Ticket Number'),
    ),
    const SizedBox(height: 16),
    FilledButton(
      onPressed: _busy
          ? null
          : () {
              if (_reference.text.trim().isEmpty) {
                setState(() => _message = 'Enter your ticket number.');
                return;
              }
              _run(_loadTicketStatus);
            },
      child: const Text('Check Status'),
    ),
    const SizedBox(height: 24),
    if (_product == 'ghaneps')
      Center(
        child: Image.asset(
          'assets/images/ghaneps_logo.png',
          width: 172,
          height: 50,
          fit: BoxFit.contain,
        ),
      ),
  ];

  List<Widget> _result() {
    final data = _status ?? {};
    final history = (data['history'] as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    final status = '${data['status'] ?? 'open'}'
        .replaceAll('_', ' ')
        .toUpperCase();
    final priority = '${data['priority'] ?? 'medium'}'.toUpperCase();
    final assignedTo = '${data['assignedToName'] ?? ''}'.trim();
    return [
      Card(
        elevation: 0,
        color: const Color(0xFFF3F6FA),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.confirmation_number_outlined,
                    color: Color(0xFF10345F),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${data['ticketReference'] ?? _reference.text}',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: const Color(0xFF10345F),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  _statusPill(status),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                '${data['title'] ?? 'Support request'}',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _detailTag('Priority', priority),
                  _detailTag('Category', '${data['category'] ?? ''}'),
                ],
              ),
              const SizedBox(height: 14),
              _detailLine('Created', _shortDate(data['createdAt'])),
              _detailLine('Last Updated', _shortDate(data['updatedAt'])),
              _detailLine(
                'Assigned To',
                assignedTo.isEmpty ? 'Awaiting assignment' : assignedTo,
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 18),
      Row(
        children: [
          _detailTabSelector('Timeline', 0),
          _detailTabSelector('Details', 1),
          _detailTabSelector('SLA', 2),
        ],
      ),
      const Divider(height: 1),
      const SizedBox(height: 12),
      if (_detailTab == 0)
        if (history.isEmpty)
          const Text('No ticket updates have been recorded yet.')
        else
          ...history.map((event) {
            final eventStatus = '${event['status'] ?? 'Update'}'.replaceAll(
              '_',
              ' ',
            );
            final message = '${event['message'] ?? ''}'.trim();
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(
                radius: 17,
                backgroundColor: Color(0xFFE7EEF8),
                child: Icon(
                  Icons.check_circle_outline,
                  color: Color(0xFF10345F),
                  size: 19,
                ),
              ),
              title: Text(
                message.isEmpty
                    ? _titleCase(eventStatus)
                    : '${event['from'] ?? 'Support Team'}: $message',
              ),
              subtitle: Text(_shortDate(event['date'])),
            );
          })
      else if (_detailTab == 1) ...[
        _detailLine(
          'Product',
          '${data['system'] ?? _productName}'.toUpperCase(),
        ),
        _detailLine('Issue Category', '${data['category'] ?? ''}'),
        _detailLine('Summary', '${data['title'] ?? 'Support request'}'),
      ] else ...[
        _detailLine('Priority', priority),
        _detailLine('Current Status', status),
        _detailLine(
          'Assigned Officer',
          assignedTo.isEmpty ? 'Awaiting assignment' : assignedTo,
        ),
        _detailLine('Last Updated', _shortDate(data['updatedAt'])),
      ],
    ];
  }

  Widget _detailTabSelector(String label, int index) => Expanded(
    child: InkWell(
      onTap: () => setState(() => _detailTab = index),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                color: _detailTab == index
                    ? const Color(0xFF10345F)
                    : Colors.black54,
                fontWeight: _detailTab == index
                    ? FontWeight.w700
                    : FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              height: 3,
              color: _detailTab == index
                  ? const Color(0xFF10345F)
                  : Colors.transparent,
            ),
          ],
        ),
      ),
    ),
  );

  Widget _statusPill(String status) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Text(status, style: const TextStyle(fontSize: 11)),
  );

  Widget _detailTag(String label, String value) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Text('$label · $value', style: const TextStyle(fontSize: 11)),
  );

  Widget _detailLine(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 105,
          child: Text(label, style: const TextStyle(color: Colors.black54)),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );

  String _shortDate(dynamic value) {
    if (value is! String || value.isEmpty) return '—';
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return value;
    return '${parsed.day.toString().padLeft(2, '0')}/${parsed.month.toString().padLeft(2, '0')}/${parsed.year} ${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}';
  }

  String _titleCase(String value) => value
      .split(' ')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');

  List<Widget> _faq() => [
    Text(
      '$_productName FAQs',
      style: Theme.of(context).textTheme.headlineSmall,
    ),
    const SizedBox(height: 8),
    const Text(
      'Sample FAQs — demo content pending confirmation by the support team.',
    ),
    for (final entry in const <(String, String)>[
      (
        'How do I reset my password?',
        'Use the password-reset option on the relevant system sign-in page. If it fails, submit a support ticket under Login & Account Access.',
      ),
      (
        'What should I include in a support ticket?',
        'Describe the steps, the time the issue occurred, and any reference number. Do not include your password or other secrets.',
      ),
      (
        'How do I follow up?',
        'Use Check Status and enter your ticket number to view its progress and support updates.',
      ),
    ])
      ExpansionTile(
        title: Text(entry.$1),
        children: [
          Padding(padding: const EdgeInsets.all(16), child: Text(entry.$2)),
        ],
      ),
    const SizedBox(height: 20),
    const Text(
      'Support coordination',
      style: TextStyle(fontWeight: FontWeight.bold),
    ),
    const ListTile(
      leading: Icon(Icons.support_agent),
      title: Text('DEMO — Support Coordinator (Example A)'),
      subtitle: Text('Placeholder only · not a real contact'),
    ),
    const ListTile(
      leading: Icon(Icons.support_agent),
      title: Text('DEMO — Support Coordinator (Example B)'),
      subtitle: Text('Placeholder only · not a real contact'),
    ),
  ];
}

class _GuestWizardProgress extends StatelessWidget {
  final int step;

  const _GuestWizardProgress({required this.step});

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF10345F);
    const teal = Color(0xFF248D88);
    final titles = const ['Select Issue Category', 'Describe Your Issue'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: SizedBox(
            width: 220,
            child: Row(
              children: [
                _stepCircle('1', active: true),
                Expanded(child: Container(height: 2, color: teal)),
                _stepCircle('2', active: step == 1),
              ],
            ),
          ),
        ),
        const SizedBox(height: 26),
        Text(
          'Step ${step + 1} of 2',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: navy,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 20),
        if (step == 1) ...[
          Text(
            titles[step],
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: const Color(0xFF2867B2),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _stepCircle(String text, {required bool active}) => Container(
    width: 54,
    height: 54,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: active ? const Color(0xFF10345F) : Colors.white,
      border: Border.all(
        color: active ? const Color(0xFF10345F) : const Color(0xFF248D88),
        width: 1.5,
      ),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: active ? Colors.white : const Color(0xFF10345F),
        fontWeight: FontWeight.w700,
        fontSize: 20,
      ),
    ),
  );
}

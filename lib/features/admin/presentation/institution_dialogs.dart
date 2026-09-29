import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hyport/core/models/enums.dart';
import 'package:hyport/features/auth/data/institution_providers.dart';
import 'package:hyport/features/auth/domain/institution.dart';

/// Shared "Add Institution" dialog for both InstitutionsScreen (mobile) and
/// DesktopInstitutionsScreen — was duplicated near-identically between the
/// two (only a width constraint differed); kept as one place so the two
/// screens can't silently drift, and so the duplicate-name guard below only
/// has to be written once.
void showAddInstitutionDialog(BuildContext context, WidgetRef ref, {double? width}) {
  final nameController = TextEditingController();
  var type = InstitutionType.mda;
  String? error;

  showDialog(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) {
        final content = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(labelText: 'Name', errorText: error),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<InstitutionType>(
              initialValue: type,
              decoration: const InputDecoration(labelText: 'Type'),
              items: InstitutionType.values.map((t) => DropdownMenuItem(value: t, child: Text(t.wireValue))).toList(),
              onChanged: (v) => setDialogState(() => type = v!),
            ),
          ],
        );

        return AlertDialog(
          title: const Text('Add Institution'),
          content: width != null ? SizedBox(width: width, child: content) : content,
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) return;

                final existing = ref.read(institutionListProvider).valueOrNull ?? const <Institution>[];
                final isDuplicate = existing.any((i) => i.name.trim().toLowerCase() == name.toLowerCase());
                if (isDuplicate) {
                  setDialogState(() => error = 'An institution with this name already exists.');
                  return;
                }

                await ref.read(institutionRepositoryProvider).create(name: name, type: type);
                if (dialogContext.mounted) Navigator.of(dialogContext).pop();
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    ),
  );
}

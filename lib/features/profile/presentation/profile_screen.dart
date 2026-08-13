import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:hyport/core/auth/auth_providers.dart';
import 'package:hyport/core/services/firebase_providers.dart';
import 'package:hyport/core/theme/app_theme.dart';
import 'package:hyport/core/widgets/branded_loader.dart';
import 'package:hyport/features/auth/data/institution_providers.dart';
import 'package:hyport/features/auth/data/user_providers.dart';
import 'package:hyport/features/auth/domain/app_user.dart';

/// MDA requester profile, following the white, information-first profile
/// screen in the user mobile reference.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _uploadingPhoto = false;

  Future<void> _updateProfilePhoto(AppUser appUser) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      _showMessage('Could not read that image. Please try another file.');
      return;
    }
    if (bytes.length > 5 * 1024 * 1024) {
      _showMessage('Profile pictures must be smaller than 5 MB.');
      return;
    }

    setState(() => _uploadingPhoto = true);
    try {
      final extension = file.extension?.toLowerCase();
      final contentType = switch (extension) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        'gif' => 'image/gif',
        _ => 'image/jpeg',
      };
      final storageRef = ref
          .read(firebaseStorageProvider)
          .ref('profile_photos/${appUser.id}/avatar');
      final snapshot = await storageRef.putData(
        bytes,
        SettableMetadata(contentType: contentType),
      );
      final url = await snapshot.ref.getDownloadURL();
      await ref
          .read(userRepositoryProvider)
          .setProfilePhotoUrl(appUser.id, url);
      _showMessage('Profile picture updated.');
    } catch (e) {
      _showMessage('Could not update profile picture: $e');
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final appUser = ref.watch(currentAppUserProvider).valueOrNull;
    if (appUser == null) return const Scaffold(body: BrandedLoaderCenter());

    final institutions = ref.watch(institutionListProvider).valueOrNull ?? const [];
    final institutionName = [
      for (final i in institutions)
        if (i.id == appUser.institutionId) i.name,
    ].firstOrNull ?? appUser.institutionType.wireValue;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          const SizedBox(height: 8),
          Center(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 112,
                  height: 112,
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.accentBlue, width: 5),
                  ),
                  child: CircleAvatar(
                    backgroundColor: AppTheme.navy.withValues(alpha: 0.1),
                    backgroundImage: appUser.profilePhotoUrl == null
                        ? null
                        : NetworkImage(appUser.profilePhotoUrl!),
                    child: appUser.profilePhotoUrl != null
                        ? null
                        : Text(
                            appUser.name.isEmpty
                                ? '?'
                                : appUser.name[0].toUpperCase(),
                            style: const TextStyle(
                              color: AppTheme.navy,
                              fontSize: 32,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                  ),
                ),
                Positioned(
                  right: -8,
                  bottom: -4,
                  child: Container(
                    width: 58,
                    height: 58,
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: Material(
                      color: AppTheme.accentBlue,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _uploadingPhoto
                            ? null
                            : () => _updateProfilePhoto(appUser),
                        child: _uploadingPhoto
                            ? const Padding(
                                padding: EdgeInsets.all(15),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(
                                Icons.camera_alt_outlined,
                                size: 29,
                                color: Colors.white,
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            appUser.name,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            appUser.role.label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Text(
            institutionName,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          _InfoCard(
            children: [
              _InfoRow(label: 'Email', value: appUser.email),
              _InfoRow(
                label: 'Phone',
                value: appUser.phone.isEmpty ? '—' : appUser.phone,
              ),
              _InfoRow(
                label: 'Institution',
                value: institutionName,
              ),
              _InfoRow(label: 'Role', value: appUser.role.label),
            ],
          ),
          const SizedBox(height: 16),
          _ActionCard(
            icon: Icons.settings_outlined,
            label: 'Settings',
            onTap: () => context.push('/settings'),
          ),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: () => ref.read(authServiceProvider).signOut(),
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('LOG OUT'),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final List<Widget> children;

  const _InfoCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(icon, color: AppTheme.navy),
        title: Text(label),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}

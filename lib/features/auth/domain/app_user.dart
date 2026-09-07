import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hyport/core/models/enums.dart';

class AppUser {
  final String id;
  final String name;
  final String email;
  final String phone;
  final UserRole role;
  final String institutionId;
  final InstitutionType institutionType;
  final DateTime createdAt;
  final bool isActive;
  final DateTime? lastActiveAt;
  final String? profilePhotoUrl;

  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.role,
    required this.institutionId,
    required this.institutionType,
    required this.createdAt,
    required this.isActive,
    this.lastActiveAt,
    this.profilePhotoUrl,
  });

  factory AppUser.fromMap(String id, Map<String, dynamic> map) {
    return AppUser(
      id: id,
      name: map['name'] as String? ?? '',
      email: map['email'] as String? ?? '',
      phone: map['phone'] as String? ?? '',
      role: UserRole.fromWire(map['role'] as String),
      institutionId: map['institutionId'] as String? ?? '',
      institutionType: InstitutionType.fromWire(
        map['institutionType'] as String? ?? 'MDA',
      ),
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isActive: map['isActive'] as bool? ?? true,
      lastActiveAt: (map['lastActiveAt'] as Timestamp?)?.toDate(),
      profilePhotoUrl: map['profilePhotoUrl'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'email': email,
    'phone': phone,
    'role': role.wireValue,
    'institutionId': institutionId,
    'institutionType': institutionType.wireValue,
    'createdAt': Timestamp.fromDate(createdAt),
    'isActive': isActive,
    'lastActiveAt': lastActiveAt != null
        ? Timestamp.fromDate(lastActiveAt!)
        : null,
    'profilePhotoUrl': profilePhotoUrl,
  };

  /// Presence: true while lastActiveAt is within the last 5 minutes.
  /// PresenceHeartbeatListener keeps lastActiveAt moving forward every ~2
  /// minutes for the lifetime of a foregrounded session (not just at
  /// sign-in), so this is a genuine "online right now" rather than a
  /// one-off sign-in stamp — see UserRepository.touchLastActive.
  bool get isRecentlyActive =>
      lastActiveAt != null &&
      DateTime.now().difference(lastActiveAt!) < const Duration(minutes: 5);

  /// Account state (enabled vs. deactivated) — a different axis from
  /// presence. Shared by the mobile and desktop user lists so the same
  /// account never reads differently between the two.
  String get accountStatusLabel => isActive ? 'Active' : 'Inactive';

  /// "Last seen" phrasing shared by the mobile and desktop user lists.
  /// Relative and self-contained (no intl) so both platforms render it
  /// identically.
  String get lastSeenLabel {
    if (isRecentlyActive) return 'Online now';
    final seen = lastActiveAt;
    if (seen == null) return 'Not signed in yet';
    final diff = DateTime.now().difference(seen);
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr ago';
    if (diff.inDays < 30) {
      return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
    }
    return '${(diff.inDays / 30).floor()} mo ago';
  }

  AppUser copyWith({
    String? name,
    String? phone,
    bool? isActive,
    String? profilePhotoUrl,
  }) {
    return AppUser(
      id: id,
      name: name ?? this.name,
      email: email,
      phone: phone ?? this.phone,
      role: role,
      institutionId: institutionId,
      institutionType: institutionType,
      createdAt: createdAt,
      isActive: isActive ?? this.isActive,
      profilePhotoUrl: profilePhotoUrl ?? this.profilePhotoUrl,
    );
  }
}

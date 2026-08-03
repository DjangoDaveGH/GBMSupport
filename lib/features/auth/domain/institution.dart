import 'package:hyport/core/models/enums.dart';

class Institution {
  final String id;
  final String name;
  final InstitutionType type;
  final List<String> focalPersonIds;

  const Institution({
    required this.id,
    required this.name,
    required this.type,
    required this.focalPersonIds,
  });

  factory Institution.fromMap(String id, Map<String, dynamic> map) {
    return Institution(
      id: id,
      name: map['name'] as String? ?? '',
      type: InstitutionType.fromWire(map['type'] as String? ?? 'MDA'),
      focalPersonIds: List<String>.from(map['focalPersonIds'] as List? ?? []),
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'type': type.wireValue,
        'focalPersonIds': focalPersonIds,
      };
}

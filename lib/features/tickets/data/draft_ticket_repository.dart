import 'package:hive_flutter/hive_flutter.dart';
import 'package:hyport/features/tickets/data/draft_ticket.dart';

/// Local queue of offline-created ticket drafts. Backed by a dynamic Hive
/// box (`Box<Map>`) rather than a generated TypeAdapter/model — keeps the
/// build free of codegen for a single small record type. See DECISIONS.md.
class DraftTicketRepository {
  static const boxName = 'draft_tickets';

  Box<Map> get _box => Hive.box<Map>(boxName);

  static Future<void> openBox() async {
    if (!Hive.isBoxOpen(boxName)) {
      await Hive.openBox<Map>(boxName);
    }
  }

  bool get _isAvailable => Hive.isBoxOpen(boxName);

  List<DraftTicket> getAllForUser(String userId) {
    if (!_isAvailable) return const [];
    return _box.values
        .map((m) => DraftTicket.fromMap(m))
        .where((d) => d.createdBy == userId)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> save(DraftTicket draft) {
    if (!_isAvailable) return Future.value();
    return _box.put(draft.localId, draft.toMap());
  }

  Future<void> delete(String localId) {
    if (!_isAvailable) return Future.value();
    return _box.delete(localId);
  }

  DraftTicket? get(String localId) {
    if (!_isAvailable) return null;
    final map = _box.get(localId);
    return map == null ? null : DraftTicket.fromMap(map);
  }
}

import 'package:flutter/foundation.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

/// Implemented by a repository that can answer from the local history when
/// the server cannot be reached. Screens show a "hors ligne" banner while
/// [servingCachedHistory] is true.
abstract interface class TeledocOfflineAware {
  ValueListenable<bool> get servingCachedHistory;
}

/// Copy of the consultation history kept on the phone, so the patient can
/// read a prescription without network (CONCEPTION.md, D45).
///
/// Rows are scoped by user id: two accounts on the same phone never see each
/// other's history. The call room is never stored (it is a secret that only
/// matters while the consultation is open).
abstract class TeledocHistoryStore {
  /// Replaces the user's whole history with the server's list.
  Future<void> replaceAll(int userId, List<TeledocConsultationDto> list);

  /// Inserts or updates one consultation.
  Future<void> save(int userId, TeledocConsultationDto consultation);

  /// Most recent first.
  Future<List<TeledocConsultationDto>> all(int userId);

  Future<TeledocConsultationDto?> byId(int userId, int id);

  Future<void> delete(int userId, int id);
}

import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../core/api/api_client.dart';
import 'foodsave_api.dart';
import 'reservation_cache.dart';

/// The client's reservations, with a local copy for offline use.
///
/// Every call goes to the server first; its answer is copied into the
/// [FoodSaveReservationCache]. When the server cannot be reached (network
/// error only, never for a refusal like 403/404), the local copy is
/// returned instead and [offline] becomes true. Cancelling always needs the
/// server.
class FoodSaveOfflineReservations {
  FoodSaveOfflineReservations(this._api, this._cache, this._userId);

  final FoodSaveApi _api;
  final FoodSaveReservationCache _cache;

  /// Signed-in user; without one, nothing is copied nor read back.
  final int? _userId;

  /// True while the screen shows the copy saved on the phone.
  final ValueNotifier<bool> offline = ValueNotifier(false);

  /// The local copy is a convenience: it is written in the background (the
  /// screen never waits for the disk) and a disk error is only logged.
  Future<void> _keep(Future<void> Function(int userId) write) async {
    final userId = _userId;
    if (userId == null) return;
    try {
      await write(userId);
    } catch (e, s) {
      developer.log(
        'Copie locale non mise à jour',
        name: 'foodsave',
        error: e,
        stackTrace: s,
      );
    }
  }

  /// Runs [remote]; on a network error answers with [local] when it has
  /// something, otherwise rethrows the original error.
  Future<T> _withFallback<T extends Object>(
    Future<T> Function() remote,
    Future<T?> Function(int userId) local,
  ) async {
    try {
      final value = await remote();
      offline.value = false;
      return value;
    } on ApiException catch (e) {
      final userId = _userId;
      if (!e.isNetworkError || userId == null) rethrow;
      T? copy;
      try {
        copy = await local(userId);
      } catch (le, s) {
        developer.log(
          'Copie locale illisible',
          name: 'foodsave',
          error: le,
          stackTrace: s,
        );
      }
      if (copy == null) rethrow;
      offline.value = true;
      return copy;
    }
  }

  /// « Mes réservations ».
  Future<List<ReservationDto>> myReservations() => _withFallback(
    () async {
      final list = await _api.myReservations();
      unawaited(_keep((uid) => _cache.replaceAll(uid, list)));
      return list;
    },
    (uid) async {
      final list = await _cache.all(uid);
      return list.isEmpty ? null : list;
    },
  );

  /// One reservation (with its QR code while it is active and paid).
  Future<ReservationDto> reservation(int id) => _withFallback(() async {
    final r = await _api.getReservation(id);
    unawaited(_keep((uid) => _cache.save(uid, r)));
    return r;
  }, (uid) => _cache.byId(uid, id));

  /// Cancelling needs the server; the copy is updated with its answer.
  Future<ReservationDto> cancel(int id) async {
    final r = await _api.cancelReservation(id);
    offline.value = false;
    unawaited(_keep((uid) => _cache.save(uid, r)));
    return r;
  }

  void dispose() => offline.dispose();
}

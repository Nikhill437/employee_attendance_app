import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/base/base_view_model.dart';
import '../../../data/repositories/lookup_repository.dart';
import '../../../data/repositories/supervisor_auth_repository.dart';
import '../../../data/repositories/supervisor_session_repository.dart';

/// Drives the supervisor login screen.
class SupervisorLoginViewModel extends BaseViewModel {
  final SupervisorAuthRepository _authRepository;
  final SupervisorSessionRepository _sessionRepository;
  final LookupRepository _lookupRepository;

  SupervisorLoginViewModel({
    SupervisorAuthRepository? authRepository,
    SupervisorSessionRepository? sessionRepository,
    LookupRepository? lookupRepository,
  }) : _authRepository = authRepository ?? SupervisorAuthRepository(),
       _sessionRepository = sessionRepository ?? SupervisorSessionRepository(),
       _lookupRepository = lookupRepository ?? LookupRepository();

  String? _errorMessage;

  String? get errorMessage => _errorMessage;

  /// Clears a message once the view has shown it, so it isn't re-surfaced on
  /// the next rebuild.
  void consumeError() => _errorMessage = null;

  /// Returns true and persists the session on success (the token itself is
  /// stored by [SupervisorAuthRepository]), so the supervisor stays signed
  /// in across app restarts until they explicitly log out; otherwise sets
  /// [errorMessage] (the backend's own reason, e.g. wrong credentials or a
  /// network error) and returns false.
  Future<bool> login({required String username, required String password}) async {
    final error = await _authRepository.authenticate(
      username: username,
      password: password,
    );
    final success = error == null;

    if (success) {
      await _sessionRepository.markLoggedIn();
      // Fire-and-forget: refreshes the department/task lookup cache in the
      // background so login isn't blocked on the network. A failed sync
      // (offline, no auth token configured yet, backend down) just leaves
      // enrollment working off whatever was cached by the last successful
      // sync — nothing here surfaces the failure to the supervisor.
      unawaited(
        _lookupRepository.syncFromRemote().catchError((Object e) {
          debugPrint('LookupRepository.syncFromRemote failed: $e');
        }),
      );
    } else {
      _errorMessage = error;
    }
    safeNotify();
    return success;
  }
}

import 'package:flutter/foundation.dart';

/// Shared behaviour for every view model in the app.
///
/// View models are plain [ChangeNotifier]s driven from the view with a
/// `ListenableBuilder`, so no state-management package is needed.
abstract class BaseViewModel extends ChangeNotifier {
  bool _disposed = false;

  bool get isDisposed => _disposed;

  /// Notifies listeners unless this view model has already been disposed.
  /// View models here outlive async work (database reads, camera capture),
  /// so a late completion must not call into a disposed notifier.
  void safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

import "tray_controller_stub.dart" if (dart.library.io) "tray_controller_io.dart";

abstract class TrayController {
  static TrayController? _instance;

  /// Singleton.
  ///
  /// Do NOT create multiple tray controller instances: on Windows the underlying
  /// `system_tray` plugin installs a global method-channel callback, so a later
  /// instance would overwrite the click handler and make the tray icon "dead".
  static TrayController get instance => _instance ??= getTrayController();

  bool get isAvailable;

  Future<void> ensureInitialized({
    required String Function() getServerUrl,
    required Future<void> Function() onQuickReview,
    bool startHidden = false,
  });

  Future<void> refreshStatus();

  Future<void> dispose();
}

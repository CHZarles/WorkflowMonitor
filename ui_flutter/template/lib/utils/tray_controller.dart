import "tray_controller_stub.dart" if (dart.library.io) "tray_controller_io.dart";

abstract class TrayController {
  static TrayController get instance => getTrayController();

  bool get isAvailable;

  Future<void> ensureInitialized({
    required String Function() getServerUrl,
    required Future<void> Function() onQuickReview,
    bool startHidden = false,
  });

  Future<void> refreshStatus();

  Future<void> dispose();
}

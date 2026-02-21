import "tray_controller.dart";

TrayController getTrayController() => _StubTrayController();

class _StubTrayController implements TrayController {
  @override
  bool get isAvailable => false;

  @override
  Future<void> ensureInitialized({
    required String Function() getServerUrl,
    required Future<void> Function() onQuickReview,
    bool startHidden = false,
  }) async {}

  @override
  Future<void> refreshStatus() async {}

  @override
  Future<void> dispose() async {}
}

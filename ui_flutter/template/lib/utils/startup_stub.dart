import "startup.dart";

StartupController getStartupController() => _StubStartupController();

class _StubStartupController implements StartupController {
  @override
  bool get isAvailable => false;

  @override
  Future<bool> isEnabled() async => false;

  @override
  Future<void> setEnabled(bool enabled, {bool startHidden = true}) async {}
}


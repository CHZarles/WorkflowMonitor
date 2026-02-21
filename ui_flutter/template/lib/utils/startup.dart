import "startup_stub.dart" if (dart.library.io) "startup_io.dart";

abstract class StartupController {
  static StartupController get instance => getStartupController();

  bool get isAvailable;

  Future<bool> isEnabled();

  Future<void> setEnabled(bool enabled, {bool startHidden = true});
}


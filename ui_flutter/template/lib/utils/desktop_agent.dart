import "desktop_agent_stub.dart" if (dart.library.io) "desktop_agent_io.dart";

class DesktopAgentResult {
  DesktopAgentResult({required this.ok, this.message});

  final bool ok;
  final String? message;
}

abstract class DesktopAgent {
  static DesktopAgent get instance => getDesktopAgent();

  bool get isAvailable;

  Future<String?> findRepoRoot();

  Future<DesktopAgentResult> start({
    required String coreUrl,
    bool restart = false,
    bool sendTitle = false,
    bool trackAudio = true,
    bool reviewNotify = true,
  });

  Future<DesktopAgentResult> stop({bool killAllByName = true});
}


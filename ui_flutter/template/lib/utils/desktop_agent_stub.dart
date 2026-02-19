import "desktop_agent.dart";

DesktopAgent getDesktopAgent() => _StubDesktopAgent();

class _StubDesktopAgent implements DesktopAgent {
  @override
  bool get isAvailable => false;

  @override
  Future<String?> findRepoRoot() async => null;

  @override
  Future<DesktopAgentResult> start({
    required String coreUrl,
    bool restart = false,
    bool sendTitle = false,
    bool trackAudio = true,
    bool reviewNotify = true,
  }) async {
    return DesktopAgentResult(ok: false, message: "not_supported");
  }

  @override
  Future<DesktopAgentResult> stop({bool killAllByName = true}) async {
    return DesktopAgentResult(ok: false, message: "not_supported");
  }
}


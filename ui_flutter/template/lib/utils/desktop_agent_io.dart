import "dart:io";

import "package:flutter/foundation.dart";

import "desktop_agent.dart";

DesktopAgent getDesktopAgent() => _IoDesktopAgent();

class _IoDesktopAgent implements DesktopAgent {
  @override
  bool get isAvailable => !kIsWeb && Platform.isWindows;

  @override
  Future<String?> findRepoRoot() async {
    if (!isAvailable) return null;

    final roots = <Directory>[];

    final env = Platform.environment["RECORDERPHONE_REPO_ROOT"];
    if (env != null && env.trim().isNotEmpty) {
      roots.add(Directory(env.trim()));
    }

    roots.add(Directory.current);

    try {
      final exeDir = File(Platform.resolvedExecutable).parent;
      roots.add(exeDir);
    } catch (_) {
      // ignore
    }

    bool looksLikeRepoRoot(Directory dir) {
      final runAgent = File("${dir.path}${Platform.pathSeparator}dev${Platform.pathSeparator}run-agent.ps1");
      final cargoToml = File("${dir.path}${Platform.pathSeparator}Cargo.toml");
      return runAgent.existsSync() && cargoToml.existsSync();
    }

    for (final base in roots) {
      var d = base;
      for (var i = 0; i < 10; i++) {
        if (looksLikeRepoRoot(d)) return d.path;
        final parent = d.parent;
        if (parent.path == d.path) break;
        d = parent;
      }
    }

    return null;
  }

  bool _exeExists(String repoRoot, String relPath) {
    return File("$repoRoot${Platform.pathSeparator}${relPath.replaceAll('/', Platform.pathSeparator)}").existsSync();
  }

  @override
  Future<DesktopAgentResult> start({
    required String coreUrl,
    bool restart = false,
    bool sendTitle = false,
    bool trackAudio = true,
    bool reviewNotify = true,
  }) async {
    if (!isAvailable) return DesktopAgentResult(ok: false, message: "not_supported");

    final repoRoot = await findRepoRoot();
    if (repoRoot == null) {
      return DesktopAgentResult(ok: false, message: "repo_root_not_found");
    }

    final runAgent = "$repoRoot${Platform.pathSeparator}dev${Platform.pathSeparator}run-agent.ps1";
    if (!File(runAgent).existsSync()) {
      return DesktopAgentResult(ok: false, message: "run_agent_missing");
    }

    final coreExeOk = _exeExists(repoRoot, "target/release/recorder_core.exe");
    final collectorExeOk = _exeExists(repoRoot, "target/release/windows_collector.exe");
    final noBuild = coreExeOk && collectorExeOk;

    final boolArg = (bool v) => v ? "\$true" : "\$false";

    final args = <String>[
      "-NoProfile",
      "-ExecutionPolicy",
      "Bypass",
      "-WindowStyle",
      "Hidden",
      "-File",
      runAgent,
      "-RepoRoot",
      repoRoot,
      "-CoreUrl",
      coreUrl,
      "-TrackAudio",
      boolArg(trackAudio),
      "-ReviewNotify",
      boolArg(reviewNotify),
    ];

    if (sendTitle) args.add("-SendTitle");
    if (restart) args.add("-Restart");
    if (noBuild) args.add("-NoBuild");

    try {
      final res = await Process.run("powershell", args, runInShell: false);
      final out = "${(res.stdout ?? "").toString().trim()}\n${(res.stderr ?? "").toString().trim()}".trim();
      if (res.exitCode == 0) {
        return DesktopAgentResult(ok: true, message: out.isEmpty ? "ok" : out);
      }
      return DesktopAgentResult(ok: false, message: out.isEmpty ? "exit_${res.exitCode}" : out);
    } catch (e) {
      return DesktopAgentResult(ok: false, message: e.toString());
    }
  }

  @override
  Future<DesktopAgentResult> stop({bool killAllByName = true}) async {
    if (!isAvailable) return DesktopAgentResult(ok: false, message: "not_supported");

    final repoRoot = await findRepoRoot();
    if (repoRoot == null) {
      return DesktopAgentResult(ok: false, message: "repo_root_not_found");
    }

    final stopAgent = "$repoRoot${Platform.pathSeparator}dev${Platform.pathSeparator}stop-agent.ps1";
    if (!File(stopAgent).existsSync()) {
      return DesktopAgentResult(ok: false, message: "stop_agent_missing");
    }

    final args = <String>[
      "-NoProfile",
      "-ExecutionPolicy",
      "Bypass",
      "-WindowStyle",
      "Hidden",
      "-File",
      stopAgent,
      "-RepoRoot",
      repoRoot,
    ];
    if (killAllByName) args.add("-KillAllByName");

    try {
      final res = await Process.run("powershell", args, runInShell: false);
      final out = "${(res.stdout ?? "").toString().trim()}\n${(res.stderr ?? "").toString().trim()}".trim();
      if (res.exitCode == 0) {
        return DesktopAgentResult(ok: true, message: out.isEmpty ? "ok" : out);
      }
      return DesktopAgentResult(ok: false, message: out.isEmpty ? "exit_${res.exitCode}" : out);
    } catch (e) {
      return DesktopAgentResult(ok: false, message: e.toString());
    }
  }
}

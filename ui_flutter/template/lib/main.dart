import "package:flutter/material.dart";

import "utils/platform_args.dart";

import "screens/app_shell.dart";
import "theme/recorder_theme.dart";

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final args = executableArgs();
  final deepLink = _extractDeepLink(args);
  final startMinimized = deepLink == null && _hasFlag(args, const ["--minimized", "--tray", "--background"]);
  runApp(RecorderPhoneApp(initialDeepLink: deepLink, startMinimized: startMinimized));
}

class RecorderPhoneApp extends StatelessWidget {
  const RecorderPhoneApp({super.key, this.initialDeepLink, this.startMinimized = false});

  final String? initialDeepLink;
  final bool startMinimized;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "RecorderPhone",
      theme: RecorderTheme.light(),
      darkTheme: RecorderTheme.dark(),
      themeMode: ThemeMode.system,
      home: AppShell(initialDeepLink: initialDeepLink, startMinimized: startMinimized),
    );
  }
}

String? _extractDeepLink(List<String> args) {
  for (final a in args) {
    final s = a.trim();
    if (s.startsWith("recorderphone://")) return s;
  }
  return null;
}

bool _hasFlag(List<String> args, List<String> flags) {
  final set = flags.map((e) => e.trim().toLowerCase()).where((e) => e.isNotEmpty).toSet();
  for (final a in args) {
    final s = a.trim().toLowerCase();
    if (set.contains(s)) return true;
  }
  return false;
}

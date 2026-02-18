import "package:flutter/material.dart";

import "utils/platform_args.dart";

import "screens/app_shell.dart";
import "theme/recorder_theme.dart";

void main() {
  final deepLink = _extractDeepLink(executableArgs());
  runApp(RecorderPhoneApp(initialDeepLink: deepLink));
}

class RecorderPhoneApp extends StatelessWidget {
  const RecorderPhoneApp({super.key, this.initialDeepLink});

  final String? initialDeepLink;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "RecorderPhone",
      theme: RecorderTheme.light(),
      darkTheme: RecorderTheme.dark(),
      themeMode: ThemeMode.system,
      home: AppShell(initialDeepLink: initialDeepLink),
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

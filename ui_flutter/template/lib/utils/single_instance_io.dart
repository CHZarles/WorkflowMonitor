import "dart:async";
import "dart:convert";
import "dart:io";

import "single_instance.dart";

const int _uiControlPort = 17611;
const String _cmdShow = "__show__";

bool _hasFlag(List<String> args, List<String> flags) {
  final set = flags.map((e) => e.trim().toLowerCase()).where((e) => e.isNotEmpty).toSet();
  for (final a in args) {
    final s = a.trim().toLowerCase();
    if (set.contains(s)) return true;
  }
  return false;
}

String? _extractDeepLink(List<String> args) {
  for (final a in args) {
    final s = a.trim();
    if (s.startsWith("recorderphone://")) return s;
  }
  return null;
}

Future<void> _forwardToPrimary(List<String> args) async {
  final msg = _extractDeepLink(args) ?? _cmdShow;

  try {
    final socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      _uiControlPort,
      timeout: const Duration(milliseconds: 250),
    );
    socket.write("$msg\n");
    await socket.flush();
    socket.destroy();
  } catch (_) {
    // If forwarding fails, fall back to starting a new instance (best effort).
  }
}

Future<SingleInstanceHandle?> ensureSingleInstanceImpl(List<String> args) async {
  // Allow overriding for debugging/troubleshooting.
  if (_hasFlag(args, const ["--no-single-instance"])) {
    return SingleInstanceHandle(messages: const Stream.empty(), dispose: () async {});
  }

  // In debug runs it is common to restart the app frequently; keep it enabled by default,
  // but do not hard-fail if something is weird (e.g. port collision).
  // Use a single-subscription stream so messages are buffered until the UI attaches a listener.
  final controller = StreamController<String>();

  ServerSocket? server;
  try {
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, _uiControlPort);
  } on SocketException {
    // Another instance is likely already running: forward and exit.
    await _forwardToPrimary(args);
    await controller.close();
    return null;
  } catch (_) {
    // Unexpected error: do not block startup.
    await controller.close();
    return SingleInstanceHandle(messages: const Stream.empty(), dispose: () async {});
  }

  unawaited(() async {
    await for (final socket in server!) {
      unawaited(() async {
        try {
          final bytes = await socket
              .timeout(const Duration(seconds: 3))
              .fold<List<int>>(<int>[], (acc, b) => acc..addAll(b));
          final text = utf8.decode(bytes, allowMalformed: true).trim();
          if (text.isNotEmpty) controller.add(text);
          socket.write("ok\n");
          await socket.flush();
        } catch (_) {
          // ignore
        } finally {
          try {
            socket.destroy();
          } catch (_) {
            // ignore
          }
        }
      }());
    }
  }());

  return SingleInstanceHandle(
    messages: controller.stream,
    dispose: () async {
      try {
        await server?.close();
      } catch (_) {
        // ignore
      }
      try {
        await controller.close();
      } catch (_) {
        // ignore
      }
    },
  );
}
